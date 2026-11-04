"""Builds the tutor's context the way the app does (`TutorChatContext.prompt`), from real fixtures.

The app's context is the only thing the tutor may ground its answers in, so every case built
here also carries `Facts`: the bars, notes, tracks and grader results the context actually
contains. The grounding scorers check the tutor's claims against those facts.

Formats follow Sources/PianoPad/PlaySession+TutorChatContext.swift and
Sources/PianoLessons/TutorChat.swift (`prompt`). Keep them in step when those change.
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Sequence, Tuple

import midi

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

PIECES = {
    "ode": ("Examples/ode-to-joy-c.mid", "Ode to Joy"),
    "mary": ("Examples/mary-had-a-little-lamb.mid", "Mary Had a Little Lamb"),
    "five": ("Examples/five-finger.mid", "Five-Finger Warm-up"),
}

# Right-hand five-finger position on C: the app's suggested fingering for these pieces.
FINGER = {"C4": 1, "D4": 2, "E4": 3, "F4": 4, "G4": 5}


@dataclass
class Facts:
    """What the context says, for checking the tutor's claims."""
    title: str = ""
    bar_count: int = 0
    bars: Dict[int, List[str]] = field(default_factory=dict)  # printed bar -> pitch names
    empty_bars: List[int] = field(default_factory=list)
    two_hands: bool = False
    time_signature: str = ""
    bpm: float = 0
    # Grader evidence: bar -> list of (kind, expected, played)
    mistakes: Dict[int, List[Tuple[str, str, str]]] = field(default_factory=dict)
    has_grades: bool = False
    has_timing: bool = False
    passed: Optional[bool] = None
    today: Optional[str] = None
    lesson_ids: List[str] = field(default_factory=list)
    goal: str = ""
    no_numbers: bool = True  # the learner hasn't asked for numbers


def _fmt(q: float) -> str:
    return f"{q:g}"


def score_block(key: str, fingering: bool = True) -> Tuple[str, Facts]:
    path, title = PIECES[key]
    s = midi.read(os.path.join(ROOT, path))
    bq = s.bar_quarters
    lines = [f"{title}. {len(s.bars)} bars. {s.numerator}/{s.denominator}, {int(s.bpm)} BPM; key signature 0 fifths, "
             f"minor false. Staves: [\"treble\"].",
             "Each event gives beat (denominator beats from 1), duration in quarter notes, pitches/rest and staff. "
             "Fingering is suggested by the app unless the source book supplies it."]
    facts = Facts(title=title, bar_count=len(s.bars), two_hands=s.tracks_with_notes > 1,
                  time_signature=f"{s.numerator}/{s.denominator}", bpm=s.bpm)
    for number, notes in enumerate(s.bars, 1):
        facts.bars[number] = [n.name for n in notes]
        line = f"Bar {number} (played bar {number}):\n"
        cursor = (number - 1) * bq
        events = []
        for n in notes:
            if n.start - cursor > 1e-6:
                events.append((cursor, n.start - cursor, "rest"))
            name = n.name + (f"[R finger {FINGER[n.name]}]" if fingering and n.name in FINGER else "")
            events.append((n.start, n.duration, name))
            cursor = n.start + n.duration
        if number * bq - cursor > 1e-6:
            events.append((cursor, number * bq - cursor, "rest"))
        if not notes:
            facts.empty_bars.append(number)
        for start, dur, what in events:
            beat = (start - (number - 1) * bq) * s.denominator / 4 + 1
            line += f" staff 1, beat {_fmt(round(beat, 3))}, duration {_fmt(round(dur, 3))}q: {what};\n"
        lines.append(line.rstrip("\n"))
    lines.append(f"Playable bar count: {len(s.bars)}. Separate hand tracks available: {facts.two_hands}. ")
    return "\n".join(lines), facts


def screen_block(*, section="Practice", phase="ready", mode="wait", speed=100, notes_recorded=0,
                 coaching=False, focus="none", awaiting_start=False, expected=(), exercise: Optional[str] = None) -> str:
    meaning = {"Practice": "the open piece's score and player, with the piece tutor",
               "Learn": "the guided course: unit map, lesson pages and ear training"}[section]
    text = (f"Section: {section} ({meaning}). Player: {phase}. Mode: {mode}. Speed: {speed}%. "
            f"Notes recorded in ongoing take: {notes_recorded}. Guide: 0/0. Listening: false. "
            f"Coaching after takes: {str(coaching).lower()}. Marked printed bars: []. Current coaching focus: {focus}. "
            f"Awaiting learner's Start practice: {str(awaiting_start).lower()}. Count-in: false. "
            "A recording clock alone does not mean the learner has played. "
            f"Keys expected now: {list(expected)}; held: []; wrong held keys: [].")
    if exercise:
        text += f" Current exercise: {exercise}."
    return text


def grade_text(*, correct: int, expected: int, mistakes: Sequence[Tuple[int, float, str, str, str]] = (),
               timing: Optional[Tuple[float, float, float, float]] = None, passed: bool = False) -> str:
    """mistakes: (bar, beat, kind, expected, played). timing: (fitted, target, rhythm error, CV)."""
    wrong = sum(1 for m in mistakes if m[2] == "wrongPitch")
    missed = sum(1 for m in mistakes if m[2] == "missed")
    extra = sum(1 for m in mistakes if m[2] == "extra")
    score = round(100 * correct / max(expected, 1))
    text = (f"Passed: {str(passed).lower()}. Notes correct {correct}/{expected}, wrong {wrong}, missed {missed}, "
            f"extra {extra}, score {score}%.")
    if timing:
        text += (f" Tempo {timing[0]:.1f} BPM (target {timing[1]:.1f}); mean rhythm error {timing[2]:.3f}; "
                 f"steadiness CV {timing[3]:.3f}.")
    else:
        text += " Timing not assessed; this is not evidence of playing in time."
    text += f"\n{score}% ({correct}/{expected} correct, {wrong} wrong, {missed} missed, {extra} extra)"
    text += "\n" + "; ".join(
        f"m{b} b{_fmt(beat)}: " + (f"played {p}, expected {e}" if k == "wrongPitch" else f"{k} {e if k == 'missed' else p}")
        for b, beat, k, e, p in mistakes)
    text += "\n" + "; ".join(f"m{b} b{_fmt(beat)} {k}, expected {e or 'none'}, played {p or 'none'}"
                             for b, beat, k, e, p in mistakes)
    return text


@dataclass
class Context:
    lesson: str = ""
    screen: str = ""
    score: str = ""
    learner: str = ""
    history: str = ""
    grades: str = ""
    available_lessons: str = ""
    goal: str = ""
    library: str = ""
    action_results: str = ""
    previous_sessions: str = ""
    progress: str = ""
    trends: str = ""
    app_guide: str = ""
    diagnostics: str = ""
    book_title: Optional[str] = None
    current_page: Optional[int] = None
    pages: List[Tuple[int, str]] = field(default_factory=list)
    page_image: Optional[str] = None  # repo-relative path
    facts: Facts = field(default_factory=Facts)

    def prompt(self) -> str:
        parts: List[str] = []
        if self.lesson:
            parts.append("Lesson: " + self.lesson)
        for label, value in [("Current screen", self.screen), ("Score data", self.score), ("Learner", self.learner),
                             ("Practice history", self.history), ("Grader evidence", self.grades),
                             ("Available lessons (IDs for openLesson)", self.available_lessons),
                             ("Musical goal", self.goal), ("Library", self.library),
                             ("Action results", self.action_results),
                             ("Previous sessions with this learner (your notes)", self.previous_sessions),
                             ("Progress", self.progress), ("This piece over time", self.trends),
                             ("App guide", self.app_guide), ("Input diagnostics", self.diagnostics)]:
            if value:
                parts.append(f"{label}:\n{value}")
        if self.book_title:
            parts.append(f"Book: {self.book_title}" + (f", the learner is on page {self.current_page}" if self.current_page else "")
                         + ("." if not self.page_image else ". A picture of that page is attached."))
        for number, text in self.pages:
            parts.append(f"Text of page {number}:\n{text}")
        return "\n\n".join(parts) if parts else "No lesson or book is open."


def practice(piece: str, *, grades: Optional[str] = None, mistakes=(), passed=False, timing=None,
             goal: str = "", today: Optional[str] = None, **screen) -> Context:
    """A learner in Practice with `piece` open: the most common context."""
    score, facts = score_block(piece)
    ctx = Context(screen=screen_block(**screen), score=score,
                  learner="Level: beginner. Hands separately so far; reads treble clef; 4 pieces passed.",
                  goal=goal or "Not set; ask what the learner wants to achieve when relevant.", facts=facts)
    if goal:
        facts.goal = goal
    if grades is not None:
        ctx.grades = grades
        facts.has_grades = True
        facts.has_timing = timing is not None
        facts.passed = passed
        for b, beat, k, e, p in mistakes:
            facts.mistakes.setdefault(b, []).append((k, e, p))
    else:
        ctx.grades = "No graded takes yet. The ongoing recording has not been graded."
    if today:
        ctx.progress = f"Today: {today}. This week: 42 min on 3 days. Last week: 65 min on 4 days."
        facts.today = today
    return ctx
