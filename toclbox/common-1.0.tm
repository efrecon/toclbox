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
        if { [info exists ::starkit::topdir] } {
            set vars::fullpath [file normalize $::starkit::topdir]
        } else {
            set vars::fullpath [file normalize $argv0]
        }
    }
    
    return $vars::fullpath
}


# ::toclbox::common::mapper -- Standard mapping
#
#       This procedure returns a mapping list (ready for string map command)
#       where the keys coming from the arguments are surrounded by a
#       "standardised" set of leading and ending tokens. This is a generic
#       procedure, used throughout the library, used for, for example, replacing
#       all occurences of %USER% with the valur of the USER environment
#       variable.
#
# Arguments:
#	lst_	Variable to set the list to
#	args	List of keys and their values.
#
# Results:
#       The list containing the substitution sugaring, or an empty list.
#
# Side Effects:
#       None.
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


# ::toclbox::common::defaults -- Set/Get defaults
#
#       The library favours storing global options to a module in a namespace
#       called "vars" or "gvars" under the main namespace. These options should
#       be led by a dash. This procedure can be used to get or set one or
#       several options in a namespace, following this convention. With no
#       arguments, the set of options and their values is returned. With one
#       argument, the value of that option is returned. With several arguments,
#       these are supposed to be options and their values and they will be set.
#       The leading dash can be omitted in all calls to this procedure. Setting
#       an option that does not exist is an error
#
# Arguments:
#	ns	Main namespace to set defaults for
#	args	No, one or even-long list of arguments (see above)
#
# Results:
#       See above
#
# Side Effects:
#       Modify matching options in sub-namespace!
proc ::toclbox::common::defaults { ns args } {
    # Access where we (by convention!) want to store our options. In practice,
    # this is the first of vars or gvars sub-namespace, but the list of
    # namespaces that we look into in turns is itself an option to this module,
    # namely -storage.
    foreach s ${vars::-storage} {
        if { [namespace exists ${ns}::$s] } {
            append ns ::$s
            break
        }
    }
    
    # Treat all the different cases: no arguments, one argument, even-long list
    # of arguments. Options should be led by the dash (-) marker, which itself
    # is an option to this module. The implementation allows the caller to omit
    # the marker when CALLING this procedure.
    set len [llength $args]
    if { $len == 0 } {
        # No arguments: Return the list of known options and their values as a
        # dictionary.
        set opts [list]
        foreach var [info vars ${ns}::${vars::-marker}*] {
            lappend opts [namespace tail $var] [set $var]
        }
        return $opts
    } elseif { $len == 1 } {
        # One option, return its value. Fail if it does not exist.
        set var ${ns}::${vars::-marker}[string trimleft [lindex $args 0] ${vars::-marker}]
        return [set $var];  # Let it fail on purpose
    } elseif { $len%2 == 0 } {
        # Even long list of options and their values. Set them, properly scream
        # and stop on non-existing options.
        foreach {k v} $args {
            set opt ${vars::-marker}[string trimleft $k ${vars::-marker}]
            set var ${ns}::$opt
            set $var $v
        }
    } else {
        return -code error "Use no arguments, one argument or an even list"
    }
}


# ::toclbox::common::pdict -- Pretty-print a dictionary
#
#       Pretty print a dictionary, adapted from http://wiki.tcl.tk/23526. This
#       will either print out all the keys (nicely formatted on the left) to the
#       channel passed as argument, or simply returned the pretty-printed output
#       when an empty channel is given.
#
# Arguments:
#	dict	Dictionary to pretty-print
#	pattern	Pattern for selecting subset of keys
#	channel	Where to print, empty for returning result instead
#
# Results:
#       Empty string or pretty-printed lines with (selected) content of
#       dictionary.
#
# Side Effects:
#       Output on channel passed as argument, whenever relevant.
proc ::toclbox::common::pdict {dict {pattern *} {channel "stdout"}} {
    # Shamelessly stolen from http://wiki.tcl.tk/23526
    set res ""
    set longest [tcl::mathfunc::max 0 {*}[lmap key [dict keys $dict $pattern] {string length $key}]]
    dict for {key value} $dict {
        if { [string match $pattern $key] } {
            set line [format "%-${longest}s = %s" $key $value]
            if { $channel eq "" } {
                append res $line "\n"
            } else {
                puts $channel $line
            }
        }
    }
    return $res
}


package provide toclbox::common 1.0
