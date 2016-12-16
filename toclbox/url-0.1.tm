package require Tcl 8.5

package require toclbox::log

namespace eval ::toclbox::url {
    namespace eval vars {
        variable alphanumeric a-zA-Z0-9._~-
        variable matcher {(?x)		# this is _expanded_ syntax
            ^
            (?: ([\w-]+) : ) ?		# <protocol scheme>
            (?: //
                (?:
                    (
                        [^@/\#?]+	     # <userinfo part of authority>
                    ) @
                )?
                (	    # <host part of authority>
                    [^/:\#?]+ |	    # host name or IPv4 address
                    \[ [^/\#?]+ \]	    # IPv6 address in square brackets
                )
                (?: : (\d+) )?		# <port part of authority>
            )?
            ( [/\?] [^\#]*)?		  # <path> (including query)
            (?: \# (.*) )?		  # <fragment>
            $
        }
        variable ports {http 80 https 443 ftp 21 imap 143 gopher 70 nntp 119 telnet 23 }
    }
    namespace export {[a-z]*}
    namespace import [namespace parent]::log::debug
    namespace ensemble create -command ::toclurl
}

proc ::toclbox::url::encode {str} {
    Init;   # Will only consume CPU cycles once.
    
    # The spec says: "non-alphanumeric characters are replaced by '%HH'"
    # 1 leave alphanumerics characters alone
    # 2 Convert every other character to an array lookup
    # 3 Escape constructs that are "special" to the tcl parser
    # 4 "subst" the result, doing all the array substitutions

    regsub -all \[^$vars::alphanumeric\] $str {$vars::map(&)} str
    # This quotes cases like $map([) or $map($) => $map(\[) ...
    regsub -all {[][{})\\]\)} $str {\\&} str
    return [subst -nocommand $str]
}


proc ::toclbox::url::decode {str} {
    # rewrite "+" back to space
    # protect \ from quoting another '\'
    set str [string map [list + { } "\\" "\\\\"] $str]

    # prepare to process all %-escapes
    regsub -all -- {%([A-Fa-f0-9][A-Fa-f0-9])} $str {\\u00\1} str

    # process \u unicode mapped chars
    return [subst -novar -nocommand $str]
}


proc ::toclbox::url::split { url } {
    set surl [dict create]
    if { [regexp -- $vars::matcher $url -> proto auth host port path anchor] } {
        dict set surl scheme $proto
        lassign [::split $auth :] username password
        dict set surl user [decode $username]
        dict set surl pwd [decode $password]
        dict set surl host $host
        if { $port eq "" && [dict exists $vars::ports $proto] } {
            set port [dict get $vars::ports $proto]
        }
        dict set surl port $port
        dict set surl query [list]
        if { [set pos [string first ? $path]] >= 0 } {
            set qry [list]
            dict set surl path /[string trimleft [string range $path 0 [expr {$pos-1}]] /]
            foreach token [::split [string range $path [expr {$pos+1}] end] &] {
                lassign [::split $token =] k v
                lappend qry [decode $k] [decode $v]
            }
            dict set surl query $qry
        } else {
            dict set surl path /[string trimleft $path /]
        }
        dict set surl fragment $anchor
    }
    return $surl
}


proc ::toclbox::url::join { args } {
    set url ""
    if { [dict exists $args scheme] } {
        append url [dict get $args scheme] ://
    } elseif { [dict exists $args port] } {
        foreach {proto p} $vars::ports {
            if { $p == [dict get $args port] } {
                dict set args scheme $proto
                append url $proto ://
                break
            }
        }
    }
    
    set auth ""
    if { [dict exists $args user] && [dict get $args user] ne "" } {
        append auth [encode [dict get $args user]]
    }
    if { [dict exists $args pwd] && [dict get $args pwd] ne ""} {
        append auth :[encode [dict get $args pwd]]
    }
    if { $auth ne "" } {
        append url $auth @
    }
    
    if { [dict exists $args host] } {
        append url [dict get $args host];   # Appends an empty string as well...
    }
    if { [dict exists $args port] && [string is integer -strict [dict get $args port]] } {
        if { [dict exists $args scheme] \
                && [dict exists $vars::ports [dict get $args scheme]] \
                && [dict get $vars::ports [dict get $args scheme]] == [dict get $args port]} {
            # Nothing here on purpose...
        } else {
            append url : [dict get $args port]
        }
    }
    if { [dict exists $args path] } {
        append url / [string trimleft [dict get $args path] /]
    } elseif { [dict exists $args host] && [dict get $args host] ne "" } {
        append url /
    }
    if { [dict exists $args query] && [llength [dict get $args query]] } {
        append qry ?
        foreach {k v} [dict get $args query] {
            append qry [encode $k] = [encode $v] &
        }
        append url [string trimright $qry &]
    }
    if { [dict exists $args anchor] } {
        append url \# [dict get $args anchor]
    }
    return $url
}


proc ::toclbox::url::Init { { force off } } {
    if { $force } {
        catch {unset vars::map}
    }
    if { ![info exists vars::map] } {
        for {set i 0} {$i <= 256} {incr i} { 
                set c [format %c $i]
                if {![string match \[$vars::alphanumeric\] $c]} {
                        set vars::map($c) %[format %.2x $i]
                }
        }
        # These are handled specially
        array set vars::map { " " + \n %0d%0a }        
    }
}