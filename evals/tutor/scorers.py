"""Deterministic scorers for one tutor reply.

Every check returns `Finding`s tagged with the metric it counts against:

- adherence     the system prompt's rules (format, length, numbers, honesty, actions)
- grounding     claims the context doesn't support (hallucination)
- followups     the suggestion chips
- task          what this particular case expects (the right action, the right refusal)

A finding is "hard" (the reply is wrong) or "soft" (worth a look; doesn't fail the case).
These run without any model, so they're cheap, repeatable and safe to gate CI on. The LLM
judge (judge.py) adds what rules can't see: is it good teaching, are the follow-ups useful.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Any, Dict, Iterable, List, Optional, Sequence, Set

from context import Facts

CONTRACT_LIMITS = {"actions": 3, "suggestions": 3, "suggestionLength": 60}
TERMINAL = {"startLesson", "openLesson", "continueLesson", "startEarTraining", "startSightReading", "stop"}
CHILD_ACTIONS = {"highlight", "playNotes", "setTempo", "stop"}
# Fields each action may set; everything else must be null (the prompt: "Unused action fields are null").
FIELDS = {
    "practicePassage": {"fromBar", "toBar", "hand", "tempoPercent", "mode", "goal"},
    "listenPassage": {"fromBar", "toBar", "hand", "tempoPercent", "mode", "goal"},
    "startLesson": {"goal", "hand", "tempoPercent", "mode"},
    "openLesson": {"lessonID", "goal"},
    "continueLesson": {"goal"},
    "gradeTake": {"goal"},
    "stop": {"goal"},
    "setGoal": {"goal", "goalDate"},
    "setTempo": {"tempoPercent", "goal"},
    "searchLibrary": {"query", "composer", "difficulty"},
    "openPiece": {"pieceRef"},
    "previewPiece": {"pieceRef"},
    "openBookPage": {"page"},
    "practiceExercise": {"exercise", "key", "octaves", "hand", "mode", "tempoPercent", "goal"},
    "playNotes": {"notes", "tempoBPM"},
    "highlight": {"bars", "keys"},
    "startEarTraining": {"level"},
    "startSightReading": {"level"},
    "planSession": {"minutes", "planSteps"},
    "openCalibration": set(),
    "switchInput": {"input"},
    "openSettings": {"section"},
    "markPlayedRight": set(),
}


@dataclass
class Finding:
    metric: str
    rule: str
    message: str
    hard: bool = True

    def as_dict(self) -> Dict[str, Any]:
        return {"metric": self.metric, "rule": self.rule, "message": self.message, "hard": self.hard}


# ----------------------------------------------------------------------------- text helpers

PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
NOTE_TOKEN = r"[A-G](?:#|♯|b|♭)?\d?"
NOTE_SEQ = re.compile(rf"(?<![A-Za-z])({NOTE_TOKEN}(?:(?:\s*[,\-–—]\s*|\s+){NOTE_TOKEN}(?![a-z]))+)(?![A-Za-z])")
NOTE_OCT = re.compile(r"(?<![A-Za-z])([A-G](?:#|♯|b|♭)?[1-7])(?![A-Za-z0-9])")
BAR_REF = re.compile(r"\b(?:bars?|measures?)\s+(\d+)(?:\s*(?:-|–|—|to|through|and|&)\s*(\d+))?", re.I)
SENTENCE = re.compile(r"(?<=[.!?\n])\s+")


def pitch_class(name: str) -> int:
    pc = PC[name[0]]
    rest = name[1:2]
    if rest in ("#", "♯"):
        pc += 1
    elif rest in ("b", "♭"):
        pc -= 1
    return pc % 12


def notes_in(sentence: str) -> List[str]:
    found = []
    for m in NOTE_SEQ.finditer(sentence):
        found += re.findall(NOTE_TOKEN, m.group(1))
    found += NOTE_OCT.findall(sentence)
    return found


def bar_refs(text: str) -> List[int]:
    out: List[int] = []
    for m in BAR_REF.finditer(text):
        a = int(m.group(1))
        b = int(m.group(2)) if m.group(2) else a
        if b < a or b - a > 40:
            b = a
        out += list(range(a, b + 1))
    return out


def sentences(text: str) -> List[str]:
    return [s.strip() for s in SENTENCE.split(text) if s.strip()]


def words(text: str) -> int:
    return len(re.findall(r"[A-Za-z0-9’']+", text))


def has_any(text: str, terms: Iterable[str]) -> bool:
    low = text.lower()
    return any(t.lower() in low for t in terms)


def tokens(text: str) -> Set[str]:
    return set(re.findall(r"[a-z0-9]+", text.lower()))


def promises_action(text: str) -> bool:
    """Port of TutorChatReply.promisesAction (Sources/PianoLessons/TutorChat.swift)."""
    lower = text.lower().replace("’", "'")
    pattern = (r"\b(i'll|i will|i'm going to|let me)\s+(now\s+)?(play|demonstrate|highlight|slow|speed|loop|light up)\b"
               r"|\blet's\s+(listen|hear)\b|\blisten( now| closely| carefully)?\s*!|\bhere'?s how it sounds\b")
    return re.search(pattern, lower) is not None


CLAIMS_DONE = re.compile(r"\bi(?:'ve| have)?\s+(?:just\s+)?(played|demonstrated|started|opened|slowed|looped|set|highlighted|saved|flagged|marked|sent|queued|added)\b"
                         r"|\bhere it is\b|\bthere you go\b", re.I)
NUMBERS = re.compile(r"\d+(?:\.\d+)?\s*%|\b\d+\s*/\s*\d+\b|\bbpm\b|\bcv\b|\brhythm error\b|\bthreshold\b|\bscore of\b", re.I)
TIMING_WORDS = re.compile(r"\b(rhythm was|timing was|in time|steady|steadier|even(ly)?|sped up|rushed|dragged|slowed down|on the beat|tempo was)\b", re.I)
PERFECT_WORDS = re.compile(r"\b(all the notes|every note|perfect(ly)?|no mistakes|flawless|100 ?%|spot on)\b", re.I)
PASS_WORDS = re.compile(r"\b(you passed|passed it|mastered|you'?re ready|ready for full speed|nailed it)\b", re.I)
MISTAKE_WORDS = re.compile(r"\b(wrong|missed|slip(ped)?|mistake|went astray|tripped|stumble[d]?|instead of)\b", re.I)
DATE = re.compile(r"\b(20\d\d-\d\d-\d\d|monday|tuesday|wednesday|thursday|friday|saturday|sunday|tomorrow|next week|in \d+ days|by the \d+)", re.I)
# The tutor offering, not the learner asking. ("Let me try bars 1-2" and "Should I use pedal?" are the learner.)
TUTOR_VOICE = re.compile(r"^(would you( like)?|do you want|want me to|shall we|how about we|i can|i could|can i help|great job|well done)\b", re.I)
HAND_WORDS = re.compile(r"\b(left hand|right hand|hands? separately|hands together|lh|rh)\b", re.I)
ASKS_NUMBERS = re.compile(r"\b(number|numbers|percent|%|score|bpm|exact|how many)\b", re.I)
ASKS_LONG = re.compile(r"\b(in detail|detailed|explain fully|step by step|everything|long|thorough)\b", re.I)


# ----------------------------------------------------------------------------- the checks

def check_schema(out: Any) -> List[Finding]:
    if not isinstance(out, dict):
        return [Finding("adherence", "schema", "reply is not a JSON object")]
    f = []
    for key, kind in (("on_topic", bool), ("reply", str), ("actions", list), ("suggestions", list)):
        if not isinstance(out.get(key), kind):
            f.append(Finding("adherence", "schema", f"`{key}` missing or not {kind.__name__}"))
    return f


def actions_of(out: Dict[str, Any]) -> List[Dict[str, Any]]:
    return [a for a in out.get("actions") or [] if isinstance(a, dict)]


def check_adherence(out: Dict[str, Any], case: Dict[str, Any], facts: Facts) -> List[Finding]:
    f: List[Finding] = []
    reply = (out.get("reply") or "").strip()
    acts = actions_of(out)
    kinds = [a.get("kind") for a in acts]
    child = case.get("audience") == "child"
    question = case.get("question", "")

    if out.get("on_topic") is False:
        if reply:
            f.append(Finding("adherence", "offtopic_empty_reply", f"off topic but reply not empty: {reply[:80]!r}"))
        if acts:
            f.append(Finding("adherence", "offtopic_no_actions", f"off topic but actions {kinds}"))
        if out.get("suggestions"):
            f.append(Finding("adherence", "offtopic_no_suggestions", "off topic but suggestions given"))
        return f
    if not reply:
        f.append(Finding("adherence", "empty_reply", "on topic with an empty reply"))

    # Length.
    if child:
        n = len([s for s in sentences(reply) if words(s) > 0])
        if n > 3:
            f.append(Finding("adherence", "child_length", f"{n} sentences to a child (max 3)"))
    elif not ASKS_LONG.search(question):
        n = words(reply)
        if n > 110:
            f.append(Finding("adherence", "length", f"{n} words (max 100)"))
        elif n > 100:
            f.append(Finding("adherence", "length", f"{n} words (max 100)", hard=False))

    # Numbers about a take, unless asked.
    if (facts.has_grades or facts.has_progress) and not ASKS_NUMBERS.search(question):
        hits = sorted({m.group(0) for m in NUMBERS.finditer(reply)})
        if hits:
            f.append(Finding("adherence", "no_numbers", f"quotes grader numbers unasked: {hits}"))
    if child and re.search(r"\d+\s*%|\bscore\b|\bgrade[sd]?\b|\bbpm\b|\bcorrect\b|\bwrong\b", reply, re.I):
        f.append(Finding("adherence", "child_grading_words", "percentages or grading words to a child"))

    # Honest about what ran: actions run after the reply.
    m = CLAIMS_DONE.search(reply)
    if m and not re.search(r"\byou(?:'ve| have)?\s+(?:just\s+)?" + re.escape(m.group(1) or ""), reply, re.I):
        f.append(Finding("adherence", "claims_done", f"says it already acted: {m.group(0)!r}"))
    if promises_action(reply) and not acts and not case.get("acted"):
        f.append(Finding("adherence", "promise_without_action", "promises to play/show something with no action"))

    # Actions.
    limit = 2 if child else CONTRACT_LIMITS["actions"]
    if len(acts) > limit:
        f.append(Finding("adherence", "too_many_actions", f"{len(acts)} actions (max {limit})"))
    if child:
        bad = [k for k in kinds if k not in CHILD_ACTIONS]
        if bad:
            f.append(Finding("adherence", "child_actions", f"actions a child can't run: {bad}"))
    for i, k in enumerate(kinds):
        if k in TERMINAL and i != len(kinds) - 1:
            f.append(Finding("adherence", "terminal_last", f"{k} isn't last in {kinds}"))
    for a in acts:
        f += check_action(a, facts, child, question, reply)
    if "practiceExercise" in kinds and len(notes_in(reply)) >= 4:
        f.append(Finding("adherence", "exercise_notes_listed", "lists the notes of an exercise the app writes and grades"))
    if "gradeTake" in kinds and not re.search(r"\bgrade|\bscore|how did i do|check (my|this|the) take", question, re.I):
        f.append(Finding("adherence", "unasked_grade", "offers gradeTake without being asked"))
    stated_goal = re.search(r"\b(my goal|i want to|i'd like to|i would like to|i'm aiming|aim to|by (next|the end))\b", question, re.I)
    if not stated_goal and ("setGoal" in kinds or any(a.get("goal") for a in acts)):
        f.append(Finding("adherence", "invented_goal", "sets a goal the learner didn't state"))
    return f


def check_action(a: Dict[str, Any], facts: Facts, child: bool, question: str, reply: str = "") -> List[Finding]:
    f: List[Finding] = []
    kind = a.get("kind")
    if kind not in FIELDS:
        return [Finding("adherence", "unknown_action", f"unknown action {kind!r}")]
    extra = sorted(k for k, v in a.items() if k != "kind" and v not in (None, [], "") and k not in FIELDS[kind])
    if extra:
        f.append(Finding("adherence", "unused_fields_null", f"{kind} sets unrelated fields {extra}", hard=False))
    tp = a.get("tempoPercent")
    lo = 40 if child else 25
    if tp is not None and not (lo <= tp <= 100):
        f.append(Finding("adherence", "tempo_range", f"{kind} tempoPercent {tp} outside {lo}–100"))
    fb, tb = a.get("fromBar"), a.get("toBar")
    if kind in ("practicePassage", "listenPassage"):
        if fb is None or tb is None:
            f.append(Finding("adherence", "passage_bars", f"{kind} without fromBar/toBar"))
        else:
            if fb > tb:
                f.append(Finding("adherence", "passage_bars", f"{kind} fromBar {fb} > toBar {tb}"))
            if tb - fb + 1 > 16:
                f.append(Finding("adherence", "passage_bars", f"{kind} spans {tb - fb + 1} bars (max 16)"))
            if facts.bar_count and (fb < 1 or tb > facts.bar_count):
                f.append(Finding("grounding", "action_bar_exists", f"{kind} bars {fb}–{tb}; the piece has {facts.bar_count}"))
            if facts.bar_count and facts.empty_bars and all(b in facts.empty_bars for b in range(fb, tb + 1)):
                f.append(Finding("grounding", "action_empty_bars", f"{kind} bars {fb}–{tb} are all rests", hard=False))
        if a.get("hand") in ("R", "L") and facts.bar_count and not facts.two_hands:
            # On a one-track piece the app ignores the hand and plays/sets up all of its notes
            # (PlaySession+TutorChatActions.swift, both listenPassage paths and practicePassage), so a
            # silent "R" changes nothing the learner sees. "L", or a reply that talks about hands, still
            # claims a part the piece doesn't have.
            silent = a["hand"] == "R" and not HAND_WORDS.search(reply)
            f.append(Finding("grounding", "hand_tracks", f"{kind} hand {a['hand']} but the piece has one track",
                             hard=not silent))
    if kind == "playNotes":
        notes = a.get("notes") or []
        cap = 8 if child else 32
        if not notes or len(notes) > cap:
            f.append(Finding("adherence", "play_notes_count", f"playNotes with {len(notes)} notes (1–{cap})"))
        for n in notes:
            for part in str(n).split("+"):
                mm = re.fullmatch(r"([A-G])(#|b)?(\d)", part.strip())
                if not mm or not (2 <= int(mm.group(3)) <= 6) or (mm.group(3) == "6" and pitch_class(part) != 0):
                    f.append(Finding("adherence", "play_notes_range", f"playNotes note {part!r} not a note in C2–C6"))
                    break
    if kind == "highlight":
        for b in a.get("bars") or []:
            if facts.bar_count and not (1 <= b <= facts.bar_count):
                f.append(Finding("grounding", "action_bar_exists", f"highlight bar {b}; the piece has {facts.bar_count}"))
    if kind == "practiceExercise" and (not a.get("exercise") or not a.get("key")):
        f.append(Finding("adherence", "exercise_fields", "practiceExercise without exercise/key"))
    if kind == "openLesson" and facts.lesson_ids and a.get("lessonID") not in facts.lesson_ids:
        f.append(Finding("grounding", "lesson_exists", f"openLesson {a.get('lessonID')!r} isn't an available lesson"))
    if kind == "openPiece" and a.get("pieceRef") and not re.fullmatch(r"#[1-5]|[a-z]+:[\w\-./]+", a["pieceRef"]):
        f.append(Finding("adherence", "piece_ref", f"openPiece pieceRef {a['pieceRef']!r} is free text, not an ID"))
    if kind == "setGoal" and a.get("goalDate"):
        explicit = re.search(r"\b20\d\d-\d\d-\d\d\b|\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b|\b\d{1,2}(st|nd|rd|th)\b", question, re.I)
        if not facts.today and not explicit:
            f.append(Finding("grounding", "invented_date",
                             f"goalDate {a['goalDate']} but the context has no today's date to count from"))
    return f


def check_grounding(out: Dict[str, Any], case: Dict[str, Any], facts: Facts) -> List[Finding]:
    f: List[Finding] = []
    if out.get("on_topic") is False:
        return f
    reply = out.get("reply") or ""
    if facts.bar_count:
        missing = sorted({b for b in bar_refs(reply) if b > facts.bar_count or b < 1})
        if missing and not re.search(r"\b(no|only|doesn't|does not|isn't|there is no|there's no)\b", reply, re.I):
            f.append(Finding("grounding", "bar_exists", f"talks about bars {missing}; the piece has {facts.bar_count}"))
        for s in sentences(reply):
            refs = sorted(set(bar_refs(s)))
            if len(refs) != 1 or refs[0] not in facts.bars:
                continue
            bar = refs[0]
            actual = facts.bars[bar]
            claimed = notes_in(s)
            if claimed and actual:
                wrong = sorted({n for n in claimed if pitch_class(n) not in {pitch_class(x) for x in actual}})
                if wrong and not MISTAKE_WORDS.search(s):
                    f.append(Finding("grounding", "bar_notes",
                                     f"bar {bar} has {actual}, reply says {claimed}: {s[:90]!r}"))
            if not actual and claimed and not re.search(r"\b(rest|silen|starts?|begins?|until|after)\b", s, re.I):
                f.append(Finding("grounding", "bar_notes", f"bar {bar} is all rests, reply gives notes {claimed}"))
            if actual and re.search(r"\b(whole[- ]bar rest|is a rest|rests? for the whole|nothing to play|no notes)\b", s, re.I):
                f.append(Finding("grounding", "bar_notes", f"bar {bar} has notes {actual}, reply calls it a rest"))
            if facts.has_grades and MISTAKE_WORDS.search(s) and facts.mistakes and bar not in facts.mistakes:
                f.append(Finding("grounding", "mistake_bar",
                                 f"puts a mistake in bar {bar}; the grader flagged {sorted(facts.mistakes)}"))
    if facts.has_grades:
        if facts.mistakes and PERFECT_WORDS.search(reply) and not re.search(r"\b(almost|nearly|not quite|except)\b", reply, re.I):
            f.append(Finding("grounding", "contradicts_grade", "calls the take perfect; the grader found mistakes"))
        if facts.passed is False and PASS_WORDS.search(reply) and not re.search(r"\b(not yet|not quite|almost)\b", reply, re.I):
            f.append(Finding("grounding", "claims_pass", "says they passed/are ready; the grader says not passed"))
        if not facts.has_timing and TIMING_WORDS.search(reply) and not re.search(r"\b(wasn't|not) (checked|assessed|measured|tracked)|note[- ]by[- ]note|wait mode", reply, re.I):
            f.append(Finding("grounding", "timing_unassessed",
                             f"judges timing ({TIMING_WORDS.search(reply).group(0)!r}) but timing wasn't assessed"))
    if not facts.today and DATE.search(reply) and not DATE.search(case.get("question", "")):
        f.append(Finding("grounding", "invented_date", f"mentions a date ({DATE.search(reply).group(0)!r}) with no date in context", hard=False))
    return f


def check_followups(out: Dict[str, Any], case: Dict[str, Any], facts: Facts) -> List[Finding]:
    f: List[Finding] = []
    sugg = [s for s in out.get("suggestions") or [] if isinstance(s, str)]
    if out.get("on_topic") is False or case.get("text_only"):
        return f
    if case.get("audience") == "child":
        if sugg:
            f.append(Finding("followups", "child_no_suggestions", "suggestions for a child (the app hides them)"))
        return f
    if not sugg:
        f.append(Finding("followups", "missing", "no follow-up suggestions", hard=case.get("expect_suggestions", False)))
        return f
    if len(sugg) > CONTRACT_LIMITS["suggestions"]:
        f.append(Finding("followups", "count", f"{len(sugg)} suggestions (the app shows 3)"))
    q = tokens(case.get("question", ""))
    seen: List[Set[str]] = []
    for s in sugg:
        if len(s.strip()) > CONTRACT_LIMITS["suggestionLength"]:
            f.append(Finding("followups", "too_long", f"{len(s)} chars (app drops > 60): {s!r}"))
        if TUTOR_VOICE.search(s.strip()):
            f.append(Finding("followups", "learner_voice", f"in the tutor's voice, not the learner's: {s!r}"))
        t = tokens(s)
        # A chip about a different bar ("bar 4" after "bar 12?") is a new question, not an echo.
        same_bars = set(bar_refs(s)) == set(bar_refs(case.get("question", "")))
        if q and t and same_bars and len(t & q) / len(t | q) > 0.7:
            f.append(Finding("followups", "echo", f"repeats the question just asked: {s!r}"))
        if any(t and len(t & o) / len(t | o) > 0.7 for o in seen):
            f.append(Finding("followups", "duplicate", f"near-duplicate chip: {s!r}", hard=False))
        seen.append(t)
        if facts.bar_count:
            bad = [b for b in bar_refs(s) if b > facts.bar_count]
            if bad:
                f.append(Finding("followups", "infeasible", f"chip about bar {bad} the piece doesn't have: {s!r}"))
            # A generated exercise (practiceExercise) has its own hand, so "left hand" is possible there.
            exercise = any(a.get("kind") == "practiceExercise" for a in actions_of(out))
            if not facts.two_hands and not exercise and re.search(r"\b(left hand|lh)\b", s, re.I):
                f.append(Finding("followups", "infeasible", f"left-hand chip on a one-track piece: {s!r}"))
    return f


def check_task(out: Dict[str, Any], case: Dict[str, Any]) -> List[Finding]:
    """What this case expects."""
    f: List[Finding] = []
    exp = case.get("expect", {})
    reply = out.get("reply") or ""
    kinds = [a.get("kind") for a in actions_of(out)]
    if "on_topic" in exp and out.get("on_topic") != exp["on_topic"]:
        f.append(Finding("task", "on_topic", f"expected on_topic={exp['on_topic']}, got {out.get('on_topic')}"))
        return f
    if "actions_any" in exp:  # several right answers, e.g. continueLesson runs the app's chosen next step
        if not any(kinds[:len(w)] == w for w in exp["actions_any"]):
            f.append(Finding("task", "actions", f"expected one of {exp['actions_any']}, got {kinds}"))
    if "actions" in exp:
        want = exp["actions"]
        if want == [] and kinds:
            f.append(Finding("task", "actions", f"expected no actions, got {kinds}"))
        elif want and kinds[:len(want)] != want:
            f.append(Finding("task", "actions", f"expected actions {want}, got {kinds}"))
    for kind, fields in exp.get("fields_if", {}).items():  # checked only when that action is present
        for a in (x for x in actions_of(out) if x.get("kind") == kind):
            for key, want in fields.items():
                if not (want(a.get(key)) if callable(want) else a.get(key) == want):
                    f.append(Finding("task", "action_field", f"{kind} {key}: expected {getattr(want, 'desc', want)!r}, got {a.get(key)!r}"))
    for k in exp.get("forbid_actions", []):
        if k in kinds:
            f.append(Finding("task", "forbidden_action", f"{k} in {kinds}"))
    for idx, fields in exp.get("fields", {}).items():
        acts = actions_of(out)
        a = acts[int(idx)] if len(acts) > int(idx) else {}
        for key, want in fields.items():
            got = a.get(key)
            ok = want(got) if callable(want) else got == want
            if not ok:
                f.append(Finding("task", "action_field", f"action {idx} {key}: expected {getattr(want, 'desc', want)!r}, got {got!r}"))
    for group in exp.get("mention", []):
        group = [group] if isinstance(group, str) else group
        if not has_any(reply, group):
            f.append(Finding("task", "mention", f"doesn't mention any of {group}"))
    for term in exp.get("not_mention", []):
        if term.lower() in reply.lower():
            f.append(Finding("task", "not_mention", f"mentions {term!r}"))
    return f


def score(out: Any, case: Dict[str, Any], facts: Facts) -> List[Finding]:
    found = check_schema(out)
    if found:
        return found
    return (check_task(out, case) + check_adherence(out, case, facts)
            + check_grounding(out, case, facts) + check_followups(out, case, facts))


def between(lo: float, hi: float):
    fn = lambda v: v is not None and lo <= v <= hi  # noqa: E731
    fn.desc = f"{lo}–{hi}"
    return fn
