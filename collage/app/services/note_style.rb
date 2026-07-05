# The house style for the station's written notes (the digest summary and the
# enrichment assembly). The precept: warmth comes only from stating true facts
# plainly and joining them naturally — never from mood, metaphor, or invented
# atmosphere. "A comforting backdrop", "a peaceful morning", "the familiar chirping"
# are the failure mode: feeling and behaviour the data never recorded.
#
# This is the deterministic backstop to the prompt — a note carrying these tells has
# editorialised past the facts, so it is rejected and the honest mechanical list
# stands in its place. Warmth is worth nothing if it costs accuracy.
module NoteStyle
  # Atmosphere / feeling / metaphor tells (never grounded in a facts object).
  TELLS = %w[
    comforting soothing peaceful serene tranquil calming restful
    delightful magical lovely charming enchanting idyllic picturesque
    backdrop symphony serenade melodious melody chorus
  ].freeze
  PHRASES = ['a treat', 'gentle reminder', 'feast for', 'music to'].freeze

  module_function

  # True when a note reaches for feeling or metaphor the facts can't support.
  def editorial?(text)
    body = text.to_s.downcase
    TELLS.any? { |w| body.match?(/\b#{w}\b/) } || PHRASES.any? { |p| body.include?(p) }
  end
end
