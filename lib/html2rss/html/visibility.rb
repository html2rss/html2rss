# frozen_string_literal: true

module Html2rss
  module Html
    ##
    # The one vocabulary of elements a sighted reader does not see, in two kinds:
    #
    # - unrendered: a +hidden+ attribute, an inline +display: none+, or a hiding utility class
    #   ({HIDDEN_CLASSES}). Neither seen nor spoken.
    # - screen-reader-only: an off-screen or visually-hidden class ({SCREEN_READER_CLASS}: +sr-only+,
    #   +visually-hidden+, +h-offscreen+, +_screen-reader-only+, +screen-reader-text+, ...). Spoken, not seen.
    #
    # +aria-hidden="true"+ is neither: the element is seen, only not spoken. Callers pick the kind they
    # need: a sponsorship label still counts when spoken ({LinkDestination::Sponsorship}), while titles
    # and item anchors keep only what is seen ({.concealed?}). Inputs are plain attribute values, so
    # SST and Nokogiri callers share it.
    module Visibility
      # Inline style that hides an element.
      HIDDEN_STYLE = /display\s*:\s*none/i
      # Utility class tokens that keep an element from rendering.
      HIDDEN_CLASSES = Set['hidden', 'd-none', 'is-hidden', 'hide'].freeze
      # Off-screen / visually-hidden class token, with an optional utility or BEM prefix (+u-+, +h-+,
      # +card__+, a leading +_+) and a +-focusable+ variant that shows only on keyboard focus.
      SCREEN_READER_CLASS = /
        \A_?(?:[a-z0-9]+(?:-|__))?
        (?:sr-only|visually-?hidden|screen-?reader-(?:only|text)|off-?screen|element-invisible)
        (?:-focusable)?\z
      /ix

      class << self
        ##
        # @param class_names [Array<String>] class tokens
        # @param style [String, nil] inline style
        # @param hidden [Boolean] whether the element carries a +hidden+ attribute
        # @return [Boolean] whether the element is not rendered at all
        def unrendered?(class_names, style:, hidden:)
          hidden || style.to_s.match?(HIDDEN_STYLE) || class_names.any? { HIDDEN_CLASSES.include?(_1) }
        end

        ##
        # @param class_names [Array<String>] class tokens
        # @return [Boolean] whether a class keeps the element off screen for screen readers only
        def screen_reader_only?(class_names) = class_names.any? { _1.match?(SCREEN_READER_CLASS) }

        ##
        # @param class_names [Array<String>] class tokens
        # @param style [String, nil] inline style
        # @param hidden [Boolean] whether the element carries a +hidden+ attribute
        # @return [Boolean] whether a sighted reader does not see the element
        def concealed?(class_names, style:, hidden:)
          unrendered?(class_names, style:, hidden:) || screen_reader_only?(class_names)
        end
      end
    end
  end
end
