##################
## Module Name     --  utils
## Original Author --  Emmanuel Frecon - emmanuel@sics.se
## Description:
##
##      This package provides a compatibility layer to the old utils package
##      that has been in used in a number of separate projects. It is meant to
##      ease transiting to the new code more easily.
##
##################
package require toclbox

namespace eval ::utils {}

::toclbox::control::alias ::utils::getopt ::toclbox::options::parse 1
::toclbox::control::alias ::utils::pullopt ::toclbox::options::pull 1
::toclbox::control::alias ::utils::pushopt ::toclbox::options::push 1
::toclbox::control::alias ::utils::chkopt ::toclbox::options::check 1

::toclbox::control::alias ::utils::debug ::toclbox::log::debug 1
::toclbox::control::alias ::utils::dbgfmt ::toclbox::log::format 1
::toclbox::control::alias ::utils::logger ::toclbox::log::logger 1
::toclbox::control::alias ::utils::verbosity ::toclbox::log::verbosity 1

::toclbox::control::alias ::utils::identifier ::toclbox::control::identifier 1
::toclbox::control::alias ::utils::dispatch ::toclbox::control::dispatch 1
::toclbox::control::alias ::utils::rdispatch ::toclbox::control::rdispatch 1
::toclbox::control::alias ::utils::mset ::toclbox::control::mset 1
::toclbox::control::alias ::utils::alias ::toclbox::control::alias 1

::toclbox::control::alias ::utils::resolve ::toclbox::text::resolve 1
::toclbox::control::alias ::utils::sed ::toclbox::text::sed 1
::toclbox::control::alias ::utils::psplit ::toclbox::text::psplit 1

::toclbox::control::alias ::utils::lclean ::toclbox::config::clean 1
::toclbox::control::alias ::utils::lscan ::toclbox::config::scan 1
::toclbox::control::alias ::utils::lread ::toclbox::config::read 1

package provide utils 0.1