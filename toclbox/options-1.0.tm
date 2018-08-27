package require Tcl 8.5

package require toclbox::log

namespace eval ::toclbox::options {
    namespace eval vars {
        variable -marker "-";    # Marker character for option
        variable version [lindex [split [file rootname [file tail [info script]]] -] end]
    }
    namespace export {[a-z]*}
    namespace import [namespace parent]::log::debug
    namespace ensemble create -command ::toclopts
}

# ::utils::UpVar -- Find true caller
#
#       Finds how many stack levels there are between the direct
#       caller to this procedure and the true caller of that caller,
#       accounting for indirection procedures aiming at making
#       available some of the local procedures from this namespace to
#       child namespaces.
#
# Arguments:
#	None.
#
# Results:
#       Number of levels to jump up the stack to access variables as
#       if upvar 1 had been used in regular cases.
#
# Side Effects:
#       None.
proc ::toclbox::options::UpVar {} {
    set signature [info level -1]
    for { set caller -1} { $caller>-10 } { incr caller -1} {
	if { [info level $caller] eq $signature } {
	    return [expr {-$caller}]
	}
    }
    return 1
}


# ::utils::getopt -- Quick options parser
#
#       Parses options (and their possible) values from an option list. The
#       parser provides full introspection. The parser accepts itself a number
#       of dash-led options, which are:
#	-value   Which variable to store the value given to the option in.
#	-option  Which variable to store which option (complete) was parsed.
#	-default Default value to give when option not present.
#
# Arguments:
#	_argv	Name of option list in caller's context
#	name	Name of option to extract (first match, can be incomplete)
#	args	Additional arguments
#
# Results:
#       Returns 1 when a matching option was found and parsed away from the
#       option list, 0 otherwise
#
# Side Effects:
#       Modifies the option list to enable being run in loops.
proc ::toclbox::options::parse {_argv name args } {
    # Get options to the option parsing procedure...
    array set OPTS {
	-value  ""
	-option ""
    }
    if { [string index [lindex $args 0] 0] ne ${vars::-marker} } {
	# Backward compatibility with old code! arguments that follow the name
	# of the option to parse are possibly the name of the variable where to
	# store the value and possibly a default value when the option isn't
	# found.
	set OPTS(-value) [lindex $args 0]
	if { [llength $args] > 1 } {
	    set OPTS(-default) [lindex $args 1]
	}
    } else {
	array set OPTS $args
    }
    
    # Access where the options are stored and possible where to store
    # side-results.
    upvar [UpVar] $_argv argv
    if { $OPTS(-value) ne "" } {
	upvar [UpVar] $OPTS(-value) var
    }
    if { $OPTS(-option) ne "" } {
	upvar [UpVar] $OPTS(-option) opt
    }
    set opt "";  # Default is no option was extracted
    if { ${vars::-marker} ne "" } {
        set name ${vars::-marker}[string trimleft $name ${vars::-marker}]
    }
    set pos [lsearch -regexp $argv ^$name]
    if {$pos>=0} {
	set to $pos
	set opt [lindex $argv $pos];  # Store the option we extracted
	# Pick the value to the option, if relevant
	if {$OPTS(-value) ne ""} {
	    set var [lindex $argv [incr to]]
	}
	# Remove option (and possibly its value from list)
	set argv [lreplace $argv $pos $to]
	return 1
    } else {
	# Did we provide a value to default?
	if { [info exists OPTS(-default)] } {
	    set var $OPTS(-default)
	}
	return 0
    }
}



proc ::toclbox::options::pull {_argv _opts} {
    upvar [UpVar] $_argv argv $_opts opts

    set opts {}
    set ddash [lsearch $argv [string repeat ${vars::-marker} 2]]
    if { $ddash >= 0 } {
	# Double dash is always on the safe-side.
	set opts [lrange $argv 0 [expr {$ddash-1}]]
	set argv [lrange $argv [expr {$ddash+1}] end]
    } else {
	# Otherwise, we give it a good guess, i.e. first non-dash-led
	# argument is the start of the arguments.
        set i 0
        while { $i < [llength $argv] } {
            set lead [string index [lindex $argv $i] 0]
            if { $lead eq ${vars::-marker} } {
                set next [string index [lindex $argv [expr {$i+1}]] 0]
                if { $next eq ${vars::-marker} } {
                    incr i
                } elseif { $i+1 >= [llength $argv] } {
                    set opts $argv
                    set argv [list]
                    return
                } else {
                    incr i 2
                }
            } else {
		break
            }
        }
        set opts [lrange $argv 0 [expr {$i-1}]]
        set argv [lrange $argv $i end]
    }
}


# ::utils::pushopt -- Option parsing with insertion/appending
#
#       The base function of this procedure is to extract an option
#       from a list of arguments and pushes its value into an array.
#       However, the procedure recognises the special characters < and
#       > at the end of the option names.  These are respectively
#       understood as prepending or appending the content extracted
#       from the arguments to the CURRENT content of the option in the
#       array.  This will typically be used to append or prepend
#       specific details to "good" defaults, instead or rewriting them
#       all.
#
# Arguments:
#	_argv	Pointer to list of arguments
#	opt	Base option to get from arguments (sans trailing < or >)
#	_ary	Destination array.
#
# Results:
#       None.
#
# Side Effects:
#       Modifies the content of the array.
proc ::toclbox::options::push { _argv opt _ary } {
    upvar $_argv argv $_ary ARY
    set modified [list]
    
    if { ${vars::-marker} ne "" } {
        set opt ${vars::-marker}[string trimleft $opt ${vars::-marker}]
    }
    set pre {}
    set on {}
    set post {}

    while { [parse argv $opt -value val -option extracted] } {
	if { [string index $extracted end] eq "<" } {
            lappend pre $val
	    lappend modified $opt
	} elseif { [string index $extracted end] eq ">" } {
            lappend post $val
	    lappend modified $opt
	} else {
            lappend on $val
	    lappend modified $opt
	}
    }

    if { [llength $modified] } {
        set val ""
        foreach v $on {
            set val $v
        }
        foreach v $pre {
            set val $v\ $val
        }
        foreach v $post {
            append val " " $v
        }
        set ARY($opt) [string trim $val]
    }
    
    return [lsort -unique $modified]
}

proc ::toclbox::options::check { _ary args } {
    upvar $_ary ARY

    set failed {}
    foreach { opt check } $args {
	set opt ${vars::-marker}[string trimleft $opt ${vars::-marker}]
	if { [info exist ARY($opt)] \
		 && ![string is $check -strict $ARY($opt)] } {
	    lappend failed $opt $check
	}
    }
    return $failed
}




package provide toclbox::options $::toclbox::options::vars::version
