"""Builds PianoPad's own demo book: public-domain beginner pieces, engraved with LilyPond.

One source of truth (PIECES below) gives three things that always agree:
  Books/PianoPad-Starter-Book.pdf    the book the app imports (from Fixtures/starter/*.ly)
  Fixtures/starter/truth/pieces.json  the answer key, in the Beyer fixtures' format
  Fixtures/starter/musicxml/<id>.musicxml, Fixtures/starter/midi/<id>.midi
usage: python3 scripts/make_demo_book.py [repo root]  then  swift test --filter StarterBookTests   (needs lilypond on PATH, or LILYPOND=…)
The melodies are traditional or long out of copyright (Beyer 1850, Beethoven 1824); the
left-hand parts of the folk songs are our own.
"""
import json, os, subprocess, sys

# Each piece: id, title, composer, time, then bars as (upper, lower), each a list of
# (pitch, duration) — pitch like "C5" or "r", duration whole/half/dotted-half/quarter/eighth.
Q, H, DH, W, E = "quarter", "half", "dotted-half", "whole", "eighth"


def q(*ps): return [(p, Q) for p in ps]


PIECES = [
    dict(id="beyer-12", title="Exercise No. 12", composer="Ferdinand Beyer, Op. 101", time="4/4",
         clefs=("treble", "treble"), bars=[
             (q("C5", "D5", "E5", "F5"), [("C4", W)]), (q("G5", "F5", "E5", "D5"), [("G4", W)]),
             (q("C5", "D5", "E5", "F5"), [("C4", W)]), (q("G5", "F5", "E5", "D5"), [("G4", W)]),
             (q("C5", "D5", "E5", "F5"), [("C4", W)]), (q("G5", "F5", "E5", "D5"), [("G4", W)]),
             (q("E5", "C5", "E5", "D5"), [("C4", H), ("G4", H)]), ([("C5", W)], [("C4", W)])]),
    dict(id="beyer-13", title="Exercise No. 13", composer="Ferdinand Beyer, Op. 101", time="4/4",
         clefs=("treble", "treble"), bars=[
             ([("C5", W)], q("C4", "D4", "E4", "F4")), ([("G5", W)], q("G4", "F4", "E4", "D4")),
             ([("C5", W)], q("C4", "D4", "E4", "F4")), ([("G5", W)], q("G4", "F4", "E4", "D4")),
             ([("C5", W)], q("C4", "D4", "E4", "F4")), ([("G5", W)], q("G4", "F4", "E4", "D4")),
             ([("C5", H), ("G5", H)], q("E4", "G4", "E4", "G4")), ([("C5", W)], [("C4", W)])]),
    dict(id="hot-cross-buns", title="Hot Cross Buns", composer="Traditional", time="4/4",
         clefs=("treble", "bass"), bars=[
             ([("E4", Q), ("D4", Q), ("C4", H)], [("C3", W)]), ([("E4", Q), ("D4", Q), ("C4", H)], [("G2", W)]),
             (q("C4", "C4", "C4", "C4"), [("C3", W)]), (q("D4", "D4", "D4", "D4"), [("G2", W)]),
             ([("E4", Q), ("D4", Q), ("C4", H)], [("G2", H), ("C3", H)])]),
    dict(id="mary-had-a-little-lamb", title="Mary Had a Little Lamb", composer="Traditional", time="4/4",
         clefs=("treble", "bass"), bars=[
             (q("E4", "D4", "C4", "D4"), [("C3", W)]), ([("E4", Q), ("E4", Q), ("E4", H)], [("C3", W)]),
             ([("D4", Q), ("D4", Q), ("D4", H)], [("G2", W)]), ([("E4", Q), ("G4", Q), ("G4", H)], [("C3", W)]),
             (q("E4", "D4", "C4", "D4"), [("C3", W)]), (q("E4", "E4", "E4", "E4"), [("C3", W)]),
             (q("D4", "D4", "E4", "D4"), [("G2", W)]), ([("C4", W)], [("C3", W)])]),
    dict(id="twinkle-twinkle", title="Twinkle, Twinkle, Little Star", composer="Traditional", time="4/4",
         clefs=("treble", "bass"), bars=[
             (q("C4", "C4", "G4", "G4"), [("C3", W)]), ([("A4", Q), ("A4", Q), ("G4", H)], [("F3", H), ("C3", H)]),
             (q("F4", "F4", "E4", "E4"), [("F3", H), ("C3", H)]), ([("D4", Q), ("D4", Q), ("C4", H)], [("G2", H), ("C3", H)]),
             (q("G4", "G4", "F4", "F4"), [("C3", H), ("F3", H)]), ([("E4", Q), ("E4", Q), ("D4", H)], [("C3", H), ("G2", H)]),
             (q("G4", "G4", "F4", "F4"), [("C3", H), ("F3", H)]), ([("E4", Q), ("E4", Q), ("D4", H)], [("C3", H), ("G2", H)]),
             (q("C4", "C4", "G4", "G4"), [("C3", W)]), ([("A4", Q), ("A4", Q), ("G4", H)], [("F3", H), ("C3", H)]),
             (q("F4", "F4", "E4", "E4"), [("F3", H), ("C3", H)]), ([("D4", Q), ("D4", Q), ("C4", H)], [("G2", H), ("C3", H)])]),
    dict(id="ode-to-joy", title="Ode to Joy", composer="Ludwig van Beethoven", time="4/4",
         clefs=("treble", "bass"), bars=[
             (q("E4", "E4", "F4", "G4"), [("C3", W)]), (q("G4", "F4", "E4", "D4"), [("G2", W)]),
             (q("C4", "C4", "D4", "E4"), [("C3", W)]), ([("E4", DH), ("D4", Q)], [("G2", W)]),
             (q("E4", "E4", "F4", "G4"), [("C3", W)]), (q("G4", "F4", "E4", "D4"), [("G2", W)]),
             (q("C4", "C4", "D4", "E4"), [("C3", W)]), ([("D4", DH), ("C4", Q)], [("G2", H), ("C3", H)])]),
    dict(id="lightly-row", title="Lightly Row", composer="Traditional", time="4/4",
         clefs=("treble", "bass"), bars=[
             ([("G4", Q), ("E4", Q), ("E4", H)], [("C3", W)]), ([("F4", Q), ("D4", Q), ("D4", H)], [("G2", W)]),
             (q("C4", "D4", "E4", "F4"), [("C3", W)]), ([("G4", Q), ("G4", Q), ("G4", H)], [("C3", W)]),
             ([("G4", Q), ("E4", Q), ("E4", H)], [("C3", W)]), ([("F4", Q), ("D4", Q), ("D4", H)], [("G2", W)]),
             (q("C4", "E4", "G4", "G4"), [("C3", W)]), ([("C4", W)], [("C3", W)])]),
]

LY_DUR = {W: "1", H: "2", DH: "2.", Q: "4", E: "8"}
BEATS = {W: 4, H: 2, DH: 3, Q: 1, E: 0.5}


def ly_pitch(p):
    if p == "r":
        return "r"
    letter, octave = p[0].lower(), int(p[1:])
    return letter + ("'" * (octave - 3) if octave >= 3 else "," * (3 - octave))


def ly_staff(bars, clef):
    return " |\n      ".join(" ".join(ly_pitch(p) + LY_DUR[d] for p, d in bar) for bar in bars) + ' \\bar "|."'


def lilypond(pieces):
    out = ['\\version "2.24.0"', '#(set-global-staff-size 26)',
           '\\paper { #(set-paper-size "letter") print-page-number = ##f tagline = ##f',
           '  markup-system-spacing.basic-distance = #10 score-markup-spacing.basic-distance = #16 }',
           '\\header { title = "PianoPad Starter Book" subtitle = "First pieces for two hands" }']
    for p in pieces:
        upper = ly_staff([u for u, _ in p["bars"]], p["clefs"][0])
        lower = ly_staff([l for _, l in p["bars"]], p["clefs"][1])
        out.append(f'''
\\score {{
  \\header {{ piece = \\markup \\fill-line {{ \\override #'(font-size . 3) \\bold "{p["title"]}" \\italic "{p["composer"]}" }} }}
  \\new PianoStaff <<
    \\new Staff = "upper" {{ \\clef {p["clefs"][0]} \\key c \\major \\time {p["time"]} \\numericTimeSignature
      {upper} }}
    \\new Staff = "lower" {{ \\clef {p["clefs"][1]} \\key c \\major \\time {p["time"]} \\numericTimeSignature
      {lower} }}
  >>
  \\layout {{ indent = 0 }}
  \\midi {{ \\tempo 4 = 90 }}
}}''')
    return "\n".join(out) + "\n"


XML_TYPE = {W: ("whole", 16, False), H: ("half", 8, False), DH: ("half", 12, True), Q: ("quarter", 4, False), E: ("eighth", 2, False)}


def musicxml(p):
    beats, beat_type = p["time"].split("/")
    measures = []
    for i, (upper, lower) in enumerate(p["bars"], 1):
        m = [f'  <measure number="{i}">']
        if i == 1:
            m.append(f'   <attributes><divisions>4</divisions><key><fifths>0</fifths></key>'
                     f'<time><beats>{beats}</beats><beat-type>{beat_type}</beat-type></time><staves>2</staves>'
                     + "".join(f'<clef number="{n}"><sign>{"G" if c == "treble" else "F"}</sign><line>{2 if c == "treble" else 4}</line></clef>'
                               for n, c in enumerate(p["clefs"], 1)) + '</attributes>')
        for staff, notes in ((1, upper), (2, lower)):
            total = 0
            for pitch, d in notes:
                kind, dur, dot = XML_TYPE[d]
                total += dur
                body = "<rest/>" if pitch == "r" else f"<pitch><step>{pitch[0]}</step><octave>{pitch[1:]}</octave></pitch>"
                m.append(f'   <note>{body}<duration>{dur}</duration><voice>{staff}</voice><type>{kind}</type>'
                         + ("<dot/>" if dot else "") + f'<staff>{staff}</staff></note>')
            if staff == 1:
                m.append(f'   <backup><duration>{total}</duration></backup>')
        if i == len(p["bars"]):
            m.append('   <barline location="right"><bar-style>light-heavy</bar-style></barline>')
        m.append('  </measure>')
        measures.append("\n".join(m))
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">
<score-partwise version="4.0">
 <work><work-title>{p["title"]}</work-title></work>
 <identification><creator type="composer">{p["composer"]}</creator></identification>
 <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
 <part id="P1">
{chr(10).join(measures)}
 </part>
</score-partwise>
'''


def truth(pieces):
    return {p["id"]: {"title": p["title"], "time": p["time"], "clefs": list(p["clefs"]),
                      "measures": [{"upper": [list(n) for n in u], "lower": [list(n) for n in l]} for u, l in p["bars"]]}
            for p in pieces}


def check(pieces):
    beats = lambda t: int(t.split("/")[0]) * 4 / int(t.split("/")[1])
    for p in pieces:
        for i, (u, l) in enumerate(p["bars"], 1):
            for name, notes in (("upper", u), ("lower", l)):
                got = sum(BEATS[d] for _, d in notes)
                assert got == beats(p["time"]), f'{p["id"]} bar {i} {name}: {got} beats'


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    check(PIECES)
    books, fx = os.path.join(root, "Books"), os.path.join(root, "Fixtures", "starter")
    for d in (books, os.path.join(fx, "truth"), os.path.join(fx, "musicxml"), os.path.join(fx, "midi")):
        os.makedirs(d, exist_ok=True)
    ly = os.path.join(fx, "PianoPad-Starter-Book.ly")
    open(ly, "w").write(lilypond(PIECES))
    json.dump(truth(PIECES), open(os.path.join(fx, "truth", "pieces.json"), "w"), indent=1)
    for p in PIECES:
        open(os.path.join(fx, "musicxml", p["id"] + ".musicxml"), "w").write(musicxml(p))
    exe = os.environ.get("LILYPOND", "lilypond")
    subprocess.run([exe, "-s", "-o", os.path.join(books, "PianoPad-Starter-Book"), ly], check=True)
    # LilyPond names the MIDI files book.midi, book-1.midi, … in score order.
    for i, p in enumerate(PIECES):
        src = os.path.join(books, "PianoPad-Starter-Book" + (f"-{i}" if i else "") + ".midi")
        os.replace(src, os.path.join(fx, "midi", p["id"] + ".midi"))
    print(f"{len(PIECES)} pieces: {books}/PianoPad-Starter-Book.pdf, answer keys in {fx}")


if __name__ == "__main__":
    main()
