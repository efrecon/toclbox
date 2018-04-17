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
        variable version       [lindex [split [file rootname [file tail [info script]]] -] end]
    }
    namespace export {[a-z]*}
    namespace import [namespace parent]::log::debug
    namespace ensemble create -command ::toclurl
}

# ::toclbox::url::encode -- URL Encode
#
#       Encode a string so that it can be properly part of a URL according to
#       RFC 3986. The code is slightly modified from one of the implementations
#       available at http://wiki.tcl.tk/14144. The implementation uses a map for
#       quick mapping of non-alphanumeric character, the map is created once and
#       only once whenever this procedure is called the first time.
#
# Arguments:
#	str	String to URL encode
#
# Results:
#       A URL encoded string.
#
# Side Effects:
#       None.
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


# ::toclbox::url::decode -- URL Decode 
#
#       Decode a string as specified by RFC 3986.
#
# Arguments:
#	str	URL encoded string
#
# Results:
#       Decoded string
#
# Side Effects:
#       None.
proc ::toclbox::url::decode {str} {
    # rewrite "+" back to space
    # protect \ from quoting another '\'
    set str [string map [list + { } "\\" "\\\\"] $str]

    # prepare to process all %-escapes
    regsub -all -- {%([A-Fa-f0-9][A-Fa-f0-9])} $str {\\u00\1} str

    # process \u unicode mapped chars
    return [subst -novar -nocommand $str]
}


# ::toclbox::url::split -- Split URL
#
#       Split a URL into all its components and return a dictionary with all
#       elements. The API is very similar to the one of ::uri::split (in
#       Tcllib), but it will also parse the query arguments. You are guaranteed
#       to find the following keys in the returned dictionary: scheme, user,
#       pwd, host, port, path, query and fragment. The query is a list
#       represented the decoded arguments that might be part of the URL.
#       Splitting recognises default ports for common protocols, so the port
#       will always be there.
#
# Arguments:
#	url	URL to split up
#
# Results:
#       Return a dictionary describing the various elements of the URL.
#
# Side Effects:
#       None.
proc ::toclbox::url::split { url } {
    set surl [dict create]
    if { [regexp -- $vars::matcher $url -> proto auth host port path anchor] } {
        dict set surl scheme $proto
        lassign [::split $auth :] username password
        dict set surl user [decode $username]
        dict set surl pwd [decode $password]
        dict set surl host $host
        # Fix port using the list of common protocols.
        if { $port eq "" && [dict exists $vars::ports $proto] } {
            set port [dict get $vars::ports $proto]
        }
        dict set surl port $port
        # Parse query, if we have one, meaning that we will split all the
        # arguments to the URL using calls to url::decode.
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


# ::toclbox::url::join -- Join URL
#
#       Join a dictionary, similar to the ones returned by the split procedure
#       into a proper URL. This implementation forgives mistakes and
#       automatically skips ports whenever these are the default ones. You
#       should be able to not specifying the scheme (as long as the port is
#       default).
#
# Arguments:
#	args	keys and values, as returned by split
#
# Results:
#       A properly formatted URL
#
# Side Effects:
#       None.
proc ::toclbox::url::join { args } {
    set url "";    # This is what we construct all along
    # Add scheme, if none, pick a proper one using the port
    if { [dict exists $args scheme] } {
        append url [dict get $args scheme] ://
    } elseif { [dict exists $args port] } {
        foreach {proto p} $vars::ports {
            if { $p == [dict get $args port] } {
                dict set args scheme $proto;   # Remember scheme for further down.
                append url $proto ://
                break
            }
        }
    }
    
    # Add authentication, but only if we had some.
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
    
    # Add the port, but skip on purpose standard ports to be able to provide
    # cleaner and leaner URLs to callers.
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
    
    # Convert the list of keys and values from the query, if any
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


# ::toclbox::url::Init -- Initialise mapping
#
#       Initialises the map that will be used to convert non-alphanumeric
#       characters.  The map is created once and only, unless forced.
#
# Arguments:
#	force	Force (re)creation of the map.
#
# Results:
#       None.
#
# Side Effects:
#       Store map in memory.
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

package provide toclbox::url $::toclbox::url::vars::version