package require Tcl 8.5

namespace eval ::toclbox {}

# Require all packages that are only 8.5 dependent.
foreach pkg [list config control log options text network url \
                    safe island firewall interp templater] {
    package require toclbox::$pkg
}

# This provides a quicker to grasp API for the whole of toclbox, without digging
# into the different packages at hand. It is largely inspired from the old utils
# library (see this utils module).
::toclbox::control::alias ::toclbox::getopt ::toclbox::options::parse 1
::toclbox::control::alias ::toclbox::pullopt ::toclbox::options::pull 1
::toclbox::control::alias ::toclbox::pushopt ::toclbox::options::push 1
::toclbox::control::alias ::toclbox::chkopt ::toclbox::options::check 1

::toclbox::control::alias ::toclbox::log ::toclbox::log::debug 1
::toclbox::control::alias ::toclbox::debug ::toclbox::log::debug 1
::toclbox::control::alias ::toclbox::dbgfmt ::toclbox::log::format 1
::toclbox::control::alias ::toclbox::logger ::toclbox::log::logger 1
::toclbox::control::alias ::toclbox::verbosity ::toclbox::log::verbosity 1

::toclbox::control::alias ::toclbox::identifier ::toclbox::control::identifier 1
::toclbox::control::alias ::toclbox::dispatch ::toclbox::control::dispatch 1
::toclbox::control::alias ::toclbox::rdispatch ::toclbox::control::rdispatch 1
::toclbox::control::alias ::toclbox::mset ::toclbox::control::mset 1
::toclbox::control::alias ::toclbox::alias ::toclbox::control::alias 1

::toclbox::control::alias ::toclbox::resolve ::toclbox::text::resolve 1
::toclbox::control::alias ::toclbox::sed ::toclbox::text::sed 1
::toclbox::control::alias ::toclbox::psplit ::toclbox::text::split 1
::toclbox::control::alias ::toclbox::split ::toclbox::text::split 1
::toclbox::control::alias ::toclbox::human ::toclbox::text::human 1
::toclbox::control::alias ::toclbox::offload ::toclbox::text::offload 1

::toclbox::control::alias ::toclbox::lclean ::toclbox::config::clean 1
::toclbox::control::alias ::toclbox::lscan ::toclbox::config::scan 1
::toclbox::control::alias ::toclbox::lread ::toclbox::config::read 1

::toclbox::control::alias ::toclbox::fullpath ::toclbox::common::fullpath 1
::toclbox::control::alias ::toclbox::mapper ::toclbox::common::mapper 1
::toclbox::control::alias ::toclbox::defaults ::toclbox::common::defaults 1
::toclbox::control::alias ::toclbox::pdict ::toclbox::common::pdict 1

::toclbox::control::alias ::toclbox::urlsplit ::toclbox::url::split 1
::toclbox::control::alias ::toclbox::urljoin ::toclbox::url::join 1
::toclbox::control::alias ::toclbox::urlencode ::toclbox::url::encode 1
::toclbox::control::alias ::toclbox::urldecode ::toclbox::url::decode 1

::toclbox::control::alias ::toclbox::https ::toclbox::network::https 1
::toclbox::control::alias ::toclbox::geturl ::toclbox::network::geturl 1

# Add 8.6 specific packages. This should be of less importance as 8.6 is stable
# and mature. But still...
if { [catch {package require Tcl 8.6} ver] == 0 } {
    foreach pkg [list exec sys] {
        package require toclbox::$pkg
    }
    
    ::toclbox::control::alias ::toclbox::exec ::toclbox::exec::run 1
    ::toclbox::control::alias ::toclbox::apparmor ::toclbox::exec::armor 1
    ::toclbox::control::alias ::toclbox::running ::toclbox::exec::running 1
    
    ::toclbox::control::alias ::toclbox::processes ::toclbox::sys::processes 1
    ::toclbox::control::alias ::toclbox::signal ::toclbox::sys::signal 1
    ::toclbox::control::alias ::toclbox::kill ::toclbox::sys::signal 1
    ::toclbox::control::alias ::toclbox::deadly ::toclbox::sys::deadly 1
}

# Export all lower-cased commands and make an ensemble to ease access to
# everything from the outside.
namespace eval ::toclbox {
    namespace export {[a-z]*}
    namespace ensemble create
}

package provide toclbox 1.0
