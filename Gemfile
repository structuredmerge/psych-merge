# frozen_string_literal: true

source "https://gem.coop"

git_source(:codeberg) { |repo_name| "https://codeberg.org/#{repo_name}" }
git_source(:gitlab) { |repo_name| "https://gitlab.com/#{repo_name}" }

# Specify your gem's dependencies in psych-merge.gemspec
gemspec

eval_gemfile "gemfiles/modular/debug.gemfile"
eval_gemfile "gemfiles/modular/coverage.gemfile"
eval_gemfile "gemfiles/modular/style.gemfile"
eval_gemfile "gemfiles/modular/documentation.gemfile"
eval_gemfile "gemfiles/modular/optional.gemfile"
eval_gemfile "gemfiles/modular/x_std_libs.gemfile"

unless ENV.fetch("KETTLE_RB_DEV", "false").casecmp("false").zero?
  require File.expand_path("../nomono/lib/nomono/bundler", __dir__)

  eval_nomono_gems(
    gems: %w[ast-merge],
    prefix: "KETTLE_RB",
    path_env: "KETTLE_RB_DEV",
    vendored_gems_env: "VENDORED_GEMS",
    vendor_gem_dir_env: "VENDOR_GEM_DIR",
    debug_env: "KETTLE_DEV_DEBUG"
  )
end
