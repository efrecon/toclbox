package require Tcl 8.5

namespace eval ::toclbox::common {
    namespace eval vars {
        variable fullpath   ""
	variable -subst     {% @ ~}
        variable -storage   {vars gvars};  # sub-namespace where we store defaults, by convention
        variable -marker    -;             # Leading single character marker for name of options, by convention
    }
    namespace export {[a-z]*}
}


# ::toclbox::common::fullpath -- Full path to program being run
#
#       Return (or set) the fully normalized path to the program being run. If
#       you are on a file system supporting symbolic links, this might not be
#       the name, nor the location of where your program is installed, but
#       rather the full path to what was requested to be started at the
#       command-line.
#
# Arguments:
#	fullpath	Path to program, used to set from outside.
#
# Results:
#       Fully normalized path to argv0, which includes the drive letter on
#       windows.
#
# Side Effects:
#       None.
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

    return [expr {[info exists lst]?$lst:[list]}]
}


proc ::toclbox::common::defaults { ns args } {
    # Access where we (by convention!) want to store our options
    foreach s ${vars::-storage} {
        if { [namespace exists ${ns}::$s] } {
            append ns ::$s
            break
        }
    }
    
    set len [llength $args]
    if { $len == 0 } {
        set opts [list]
        foreach var [info vars ${ns}::${vars::-marker}*] {
            lappend opts [namespace tail $var] [set $var]
        }
        return $opts
    } elseif { $len == 1 } {
        set var ${ns}::${vars::-marker}[string trimleft [lindex $args 0] ${vars::-marker}]
        return [set $var];  # Let it fail on purpose
    } elseif { $len%2 == 0 } {
        foreach {k v} $args {
            set opt ${vars::-marker}[string trimleft $k ${vars::-marker}]
            set var ${ns}::$opt
            set $var $v
        }
    } else {
        return -code error "Use no arguments, one argument or an even list"
    }
}

package provide toclbox::common 1.0
