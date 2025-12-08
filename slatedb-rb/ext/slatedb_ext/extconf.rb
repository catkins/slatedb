# frozen_string_literal: true

require "mkmf"
require "rb_sys/mkmf"

# Point to the Cargo.toml in the gem root directory
create_rust_makefile("slatedb/slatedb_ext") do |r|
  r.extra_rustflags = ["--cfg", "ruby_build"]
end
