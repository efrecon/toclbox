package require Tcl 8.5

namespace eval ::toclbox::common {
    namespace eval vars {
        variable fullpath   ""
	variable -subst     {% @ ~}
    }
    namespace export {[a-z]*}
    namespace ensemble create -command ::toclbox
}

proc ::toclbox::common::fullpath { {fullpath ""} } {
    global argv0
    
    if { $fullpath ne "" } {
        set vars::fullpath $fullpath
    }
    
    if { $vars::fullpath eq "" } {
        set vars::fullpath [file normalize $argv0]
    }
    
    return $vars::fullpath
}


proc ::toclbox::common::mapper { _lst args } {
    if { $_lst ne "" } {
	upvar $_lst lst
    }

    foreach {k v} $args {
	foreach s ${vars::-subst} {
	    lappend lst $s$k$s $v
	}
    }

    return $lst
}


package provide toclbox::common 1.0
