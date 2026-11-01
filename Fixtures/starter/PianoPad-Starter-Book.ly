\version "2.24.0"
#(set-global-staff-size 26)
\paper { #(set-paper-size "letter") print-page-number = ##f tagline = ##f
  markup-system-spacing.basic-distance = #10 score-markup-spacing.basic-distance = #16 }
\header { title = "PianoPad Starter Book" subtitle = "First pieces for two hands" }

\score {
  \header { piece = \markup \fill-line { \override #'(font-size . 3) \bold "Exercise No. 12" \italic "Ferdinand Beyer, Op. 101" } }
  \new PianoStaff <<
    \new Staff = "upper" { \clef treble \key c \major \time 4/4 \numericTimeSignature
      c''4 d''4 e''4 f''4 |
      g''4 f''4 e''4 d''4 |
      c''4 d''4 e''4 f''4 |
      g''4 f''4 e''4 d''4 |
      c''4 d''4 e''4 f''4 |
      g''4 f''4 e''4 d''4 |
      e''4 c''4 e''4 d''4 |
      c''1 \bar "|." }
    \new Staff = "lower" { \clef treble \key c \major \time 4/4 \numericTimeSignature
      c'1 |
      g'1 |
      c'1 |
      g'1 |
      c'1 |
      g'1 |
      c'2 g'2 |
      c'1 \bar "|." }
  >>
  \layout { indent = 0 }
  \midi { \tempo 4 = 90 }
}

\score {
  \header { piece = \markup \fill-line { \override #'(font-size . 3) \bold "Exercise No. 13" \italic "Ferdinand Beyer, Op. 101" } }
  \new PianoStaff <<
    \new Staff = "upper" { \clef treble \key c \major \time 4/4 \numericTimeSignature
      c''1 |
      g''1 |
      c''1 |
      g''1 |
      c''1 |
      g''1 |
      c''2 g''2 |
      c''1 \bar "|." }
    \new Staff = "lower" { \clef treble \key c \major \time 4/4 \numericTimeSignature
      c'4 d'4 e'4 f'4 |
      g'4 f'4 e'4 d'4 |
      c'4 d'4 e'4 f'4 |
      g'4 f'4 e'4 d'4 |
      c'4 d'4 e'4 f'4 |
      g'4 f'4 e'4 d'4 |
      e'4 g'4 e'4 g'4 |
      c'1 \bar "|." }
  >>
  \layout { indent = 0 }
  \midi { \tempo 4 = 90 }
}

\score {
  \header { piece = \markup \fill-line { \override #'(font-size . 3) \bold "Hot Cross Buns" \italic "Traditional" } }
  \new PianoStaff <<
    \new Staff = "upper" { \clef treble \key c \major \time 4/4 \numericTimeSignature
      e'4 d'4 c'2 |
      e'4 d'4 c'2 |
      c'4 c'4 c'4 c'4 |
      d'4 d'4 d'4 d'4 |
      e'4 d'4 c'2 \bar "|." }
    \new Staff = "lower" { \clef bass \key c \major \time 4/4 \numericTimeSignature
      c1 |
      g,1 |
      c1 |
      g,1 |
      g,2 c2 \bar "|." }
  >>
  \layout { indent = 0 }
  \midi { \tempo 4 = 90 }
}

\score {
  \header { piece = \markup \fill-line { \override #'(font-size . 3) \bold "Mary Had a Little Lamb" \italic "Traditional" } }
  \new PianoStaff <<
    \new Staff = "upper" { \clef treble \key c \major \time 4/4 \numericTimeSignature
      e'4 d'4 c'4 d'4 |
      e'4 e'4 e'2 |
      d'4 d'4 d'2 |
      e'4 g'4 g'2 |
      e'4 d'4 c'4 d'4 |
      e'4 e'4 e'4 e'4 |
      d'4 d'4 e'4 d'4 |
      c'1 \bar "|." }
    \new Staff = "lower" { \clef bass \key c \major \time 4/4 \numericTimeSignature
      c1 |
      c1 |
      g,1 |
      c1 |
      c1 |
      c1 |
      g,1 |
      c1 \bar "|." }
  >>
  \layout { indent = 0 }
  \midi { \tempo 4 = 90 }
}

\score {
  \header { piece = \markup \fill-line { \override #'(font-size . 3) \bold "Twinkle, Twinkle, Little Star" \italic "Traditional" } }
  \new PianoStaff <<
    \new Staff = "upper" { \clef treble \key c \major \time 4/4 \numericTimeSignature
      c'4 c'4 g'4 g'4 |
      a'4 a'4 g'2 |
      f'4 f'4 e'4 e'4 |
      d'4 d'4 c'2 |
      g'4 g'4 f'4 f'4 |
      e'4 e'4 d'2 |
      g'4 g'4 f'4 f'4 |
      e'4 e'4 d'2 |
      c'4 c'4 g'4 g'4 |
      a'4 a'4 g'2 |
      f'4 f'4 e'4 e'4 |
      d'4 d'4 c'2 \bar "|." }
    \new Staff = "lower" { \clef bass \key c \major \time 4/4 \numericTimeSignature
      c1 |
      f2 c2 |
      f2 c2 |
      g,2 c2 |
      c2 f2 |
      c2 g,2 |
      c2 f2 |
      c2 g,2 |
      c1 |
      f2 c2 |
      f2 c2 |
      g,2 c2 \bar "|." }
  >>
  \layout { indent = 0 }
  \midi { \tempo 4 = 90 }
}

\score {
  \header { piece = \markup \fill-line { \override #'(font-size . 3) \bold "Ode to Joy" \italic "Ludwig van Beethoven" } }
  \new PianoStaff <<
    \new Staff = "upper" { \clef treble \key c \major \time 4/4 \numericTimeSignature
      e'4 e'4 f'4 g'4 |
      g'4 f'4 e'4 d'4 |
      c'4 c'4 d'4 e'4 |
      e'2. d'4 |
      e'4 e'4 f'4 g'4 |
      g'4 f'4 e'4 d'4 |
      c'4 c'4 d'4 e'4 |
      d'2. c'4 \bar "|." }
    \new Staff = "lower" { \clef bass \key c \major \time 4/4 \numericTimeSignature
      c1 |
      g,1 |
      c1 |
      g,1 |
      c1 |
      g,1 |
      c1 |
      g,2 c2 \bar "|." }
  >>
  \layout { indent = 0 }
  \midi { \tempo 4 = 90 }
}

\score {
  \header { piece = \markup \fill-line { \override #'(font-size . 3) \bold "Lightly Row" \italic "Traditional" } }
  \new PianoStaff <<
    \new Staff = "upper" { \clef treble \key c \major \time 4/4 \numericTimeSignature
      g'4 e'4 e'2 |
      f'4 d'4 d'2 |
      c'4 d'4 e'4 f'4 |
      g'4 g'4 g'2 |
      g'4 e'4 e'2 |
      f'4 d'4 d'2 |
      c'4 e'4 g'4 g'4 |
      c'1 \bar "|." }
    \new Staff = "lower" { \clef bass \key c \major \time 4/4 \numericTimeSignature
      c1 |
      g,1 |
      c1 |
      c1 |
      c1 |
      g,1 |
      c1 |
      c1 \bar "|." }
  >>
  \layout { indent = 0 }
  \midi { \tempo 4 = 90 }
}
