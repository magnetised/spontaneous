# encoding: UTF-8

module Spontaneous
  module Constants
    EMPTY = "".freeze
    SLASH = "/".freeze
    DASH = "-".freeze
    AMP = "&".freeze
    DOT = ".".freeze
    QUESTION = "?".freeze
    LF = "\n".freeze

    ENV_REVISION_NUMBER = "SPOT_REVISION".freeze
    ENV_ROOT = "SPOT_ROOT".freeze

    RE_QUOTES = /['"]/.freeze
    RE_FLATTEN = /[^\.a-z0-9-]+/.freeze
    RE_FLATTEN_REPEAT = /\-+/.freeze
    RE_FLATTEN_TRAILING = /(^\-|\-$)/.freeze
  end
end
