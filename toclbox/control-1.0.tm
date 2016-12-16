package require Tcl 8.5

package require toclbox::log

namespace eval ::toclbox::control {
    namespace eval vars {
        variable generator  0
	variable -clamp     4
        variable -separator ""
    }
    namespace export {[a-z]*}
    namespace import [namespace parent]::log::debug
    namespace ensemble create -command ::toclctrl
}

# ::toclbox::control::identifier -- Return a unique identifier
#
#       Generate a well-formated unique identifier to be used, for
#       example, to generate variable names or similar. When not prefixed, this
#       identifier can be understood as a number.
#
# Arguments:
#	pfx	String prefix to prepend to id, empty for none
#
# Results:
#       A (possibly prefixed) unique identifier in space and time
#       (almost).
#
# Side Effects:
#       None.
proc ::toclbox::control::identifier { {pfx "" } } {
    set clamp [expr int(1e${vars::-clamp})]; # NO CURLY-BRACES on purpose!!
    # Convert hostname to a number, once and only once.
    if { ![info exists vars::host] } {
        set vars::host 0
        foreach c [split [info hostname] ""] {
            set vars::host [expr {($vars::host + [scan $c %c])%$clamp}]
        }
    }
    # Increment a counter
    set unique [expr {[incr vars::generator]%$clamp}]
    # Get current time.
    set now [expr {[clock clicks -milliseconds]%$clamp}]
    # Now generate a unique identifier using the clamping specification. Place
    # the timestamp at the beginning to maximise the chances to fail.
    return [join [list $pfx \
                        [format "%.${vars::-clamp}d" $now] \
                        [format "%.${vars::-clamp}d" $vars::host] \
                        [format "%.${vars::-clamp}d" $unique]] \
                ${vars::-separator}]
}


# ::utils::dispatch -- Library dispatcher
#
#       This is a generic library dispatcher that is used to offer a
#       tk-style object-like API for objects that would be created in
#       another namespace.  This will refuse to dispatch protected
#       (internal) procedures.
#
# Arguments:
#	obj	Identifier of object (typically from utils::identifier)
#	ns	FQ namespace where to dispatch
#	method	Method to call (i.e. one of the exported procs in the namespace)
#	args	Arguments to pass to the procedure after the identifier
#
# Results:
#       Whatever is returned by the called procedure.
#
# Side Effects:
#       None.
proc ::toclbox::control::dispatch { obj ns method args} {
    if { [string match \[a-z\] [string index $method 0]] } {
	if { [info commands ${ns}::${method}] eq "" } {
	    return -code error "Cannot find $method in $ns!"
	}
    } else {
	return -code error "$method is internal to $ns!"
    }
    namespace inscope $ns $method $obj {*}$args
}


proc ::toclbox::control::rdispatch { obj ns methods method args} {
    foreach meths $methods {
	foreach m $meths {
	    if { [string equal $m $method] } {
		return [dispatch $obj $ns [lindex $meths 0] {*}$args]
	    }
	}
    }
    return -code error "$method is not allowed in $ns!"
}


proc ::toclbox::control::mset { ns varvals {pfx ""} } {
    foreach {k v} $varvals {
	if { $pfx ne "" } {
	    set k ${pfx}[string trimleft $k $pfx]
	}
	if { [info exists ${ns}::${k}] } {
	    set ${ns}::${k} $v
	}
    }

    set state {}
    foreach v [info vars ${ns}::${pfx}*] {
	lappend state [lindex [split $v ":"] end] [set $v]
    }
    return $state
} 

# From http://wiki.tcl.tk/38650
proc ::toclbox::control::alias { alias target { force 0 } } {
    if { $force } {
        catch {uplevel [list rename [namespace which $alias] {}]}
    }
    set fulltarget [uplevel [list namespace which $target]]
    if {$fulltarget eq {}} {
        return -code error [list {no such command} $target]
    }
    set save [namespace eval [namespace qualifiers $fulltarget] {namespace export}]
    namespace eval [namespace qualifiers $fulltarget] {namespace export *}
    while {[namespace exists [
        set tmpns [namespace current]::[info cmdcount]]]} {}
    set code [catch {set newcmd [namespace eval $tmpns [
        string map [list @{fulltarget} [list $fulltarget]] {
        namespace import @{fulltarget}
    }]]} cres copts]
    namespace eval [namespace qualifiers $fulltarget] [
        list namespace export {*}$save]
    if {$code} {
        return -options $copts $cres
    }
    uplevel [list rename ${tmpns}::[namespace tail $target] $alias]
    namespace delete $tmpns 
    return [uplevel [list namespace which $alias]]    
}

package provide toclbox::control 1.0