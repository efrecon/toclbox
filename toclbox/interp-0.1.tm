package require Tcl 8.5

package require toclbox::log
package require toclbox::safe
package require toclbox::island
package require toclbox::firewall



namespace eval ::toclbox::interp {
    namespace export {[a-z]*};   # Convention: export all lowercase 
    namespace eval vars {
        variable version       [lindex [split [file rootname [file tail [info script]]] -] end]        
    }
    namespace import [namespace parent]::log::debug
}

proc ::toclbox::interp::create { fpath args } {
    # Pick away -safe option and create interpreter accordingly
    set safe [lsearch -glob $args -s*]
    if { $safe >= 0 } {
        set args [lreplace $args $safe $safe]
        set slave [::safe::interpCreate]
    } else {
        set slave [interp create]
    }

    # Parse options and relay those into calls to island and/or
    # firewall modules
    foreach {opt value} $args {
        switch -glob -- [string tolower [string trimleft $opt -]] {
            "ac*" {
                # -access enables access to local files or
                # directories
                ::toclbox::island::add $slave $value
            }
            "al*" {
                # -allow enables access to remote servers
                lassign [split $value :] host port
                ::toclbox::firewall::allow $slave $host $port
            }
            "d*" {
                # -deny refrains access to remote servers
                lassign [split $value :] host port
                ::toclbox::firewall::deny $slave $host $port
            }
            "p*" {
                # -package arranges for the plugin to be able to
                # access a given package.
                set version ""
                if { [regexp {:(\d+(\.\d+)*)} $value - version] } {
                    set pkg [regsub {:(\d+(\.\d+)*)} $value ""]
                } else {
                    set pkg $value
                }
                switch -- $pkg {
                    "http" {
                        debug debug "Helping out package $pkg"
                        ::toclbox::safe::environment $slave * "" tcl_platform
                        ::toclbox::safe::alias $slave encoding ::toclbox::safe::invoke $slave encoding
                    }
                }
                ::toclbox::safe::package $slave $pkg $version
            }
            "e*" {
                # -environement to pass/set environment variables.
                set equal [string first "=" $value]
                if { $equal >= 0 } {
                    set varname [string trim [string range $value 0 [expr {$equal-1}]]]
                    set value [string trim [string range $value [expr {$equal+1}] end]]
                    ::toclbox::safe::envset $slave $varname $value
                } else {
                    ::toclbox::safe::environment $slave $value
                }
            }
        }
    }

    if { $fpath ne "" } {
        debug info "Sourcing content of $fpath"
        if { $safe >= 0 } {
            if { [catch {$slave invokehidden source $fpath} res] } {
                debug error "Cannot load plugin at $fpath: $res"
                interp delete $slave
                set slave ""
            }
        } else {
            if { [catch {$slave eval source $fpath} res] } {
                debug error "Cannot load plugin at $fpath: $res"
                interp delete $slave
                set slave ""
            }
        }
    }

    return $slave
}

package provide toclbox::iinterp $::toclbox::interp::vars::version