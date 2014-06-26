module TermWin

include( "ccall.jl" )
include( "readtoken.jl" )
include( "readtoken.orig.jl")
include( "tree.jl" )

export tshow

rootwin = nothing
callcount = 0
const COLOR_BLACK   = 0
const COLOR_RED     = 1
const COLOR_GREEN   = 2
const COLOR_YELLOW  = 3
const COLOR_BLUE    = 4
const COLOR_MAGENTA = 5
const COLOR_CYAN    = 6
const COLOR_WHITE   = 7

const NCURSES_ATTR_SHIFT =8
function NCURSES_BITS( m, shf)
    m << (shf + NCURSES_ATTR_SHIFT)
end

const A_NORMAL     = uint32(0)
const A_ATTRIBUTES = ~uint32(0)
const A_CHARTEXT   = (NCURSES_BITS(uint32(1),0) - uint32(1))
const A_COLOR      = NCURSES_BITS((uint32(1) << 8) - uint32(1),0)
const A_STANDOUT   = NCURSES_BITS(uint32(1),8)
const A_UNDERLINE  = NCURSES_BITS(uint32(1),9)
const A_REVERSE    = NCURSES_BITS(uint32(1),10)
const A_BLINK      = NCURSES_BITS(uint32(1),11)
const A_DIM        = NCURSES_BITS(uint32(1),12)
const A_BOLD       = NCURSES_BITS(uint32(1),13)
const A_ALTCHARSET = NCURSES_BITS(uint32(1),14)
const A_INVIS      = NCURSES_BITS(uint32(1),15)
const A_PROTECT    = NCURSES_BITS(uint32(1),16)
const A_HORIZONTAL = NCURSES_BITS(uint32(1),17)
const A_LEFT       = NCURSES_BITS(uint32(1),18)
const A_LOW        = NCURSES_BITS(uint32(1),19)
const A_RIGHT      = NCURSES_BITS(uint32(1),20)
const A_TOP        = NCURSES_BITS(uint32(1),21)
const A_VERTICAL   = NCURSES_BITS(uint32(1),22)

function initsession()
    global rootwin, libncurses
    if rootwin == nothing || rootwin == C_NULL
        rootwin = ccall(dlsym(libncurses, :initscr), Ptr{Void}, ()) # rootwin is stdscr
        ccall( dlsym( libncurses, :keypad ), Void, (Ptr{Void}, Bool), rootwin, true );
        if rootwin == C_NULL
            println( "cannot create root win in ncurses")
            return
        end
        if !has_colors()
            ccall( dlsym( libncurses, :endwin), Void, () )
            throw( "terminal doesn't support colors")
        end
        start_color()
        init_pair( 1, COLOR_BLACK, COLOR_WHITE )
        keypad( rootwin, true )
        nodelay( rootwin, false )
        notimeout( rootwin, true )
    end
end

function endsession()
    global rootwin, libncurses
    if rootwin != nothing
        ccall( dlsym( libncurses, :endwin), Void, () )
        rootwin = nothing
    end
end

function wordwrap( x::String, width::Int )
    spaceleft = width
    lines = String[]
    currline = ""
    words = split( x, " ", true ) # don't keep empty words
    for w in words
        wlen = length(w)
        if wlen>width && spaceleft == width
            push!( lines, SubString( w, 1, width-3 ) * " .." )
        elseif wlen+1 > spaceleft
            push!( lines, currline )
            currline = w * " "
            spaceleft = width - wlen - 1
        else
            currline = currline * w * " "
            spaceleft = spaceleft - wlen -1
        end
    end
    if currline != ""
        push!(lines, currline )
    end
    return lines
end

function tshow_( x::Number; title = string(typeof( x )) )
    s = string( x )
    len = length(s)
    width = max( 21, len, length(title) ) + 4
    win = winnewcenter( 3, width )
    panel = new_panel( win )
    box( win,  0, 0 )
    keyhint = "[Esc to continue]"

    if title != ""
        mvwprintw( win, 0, int( ( width - length(title) )/2 ), "%s", title )
    end
    mvwprintw( win, 1, width-len-2, "%s", s )
    mvwprintw( win, 2, int( (width-length(keyhint))/2), "%s", keyhint )

    update_panels()
    doupdate()
    while( (readtoken( win )) != :esc ) end
    del_panel( panel )
    delwin( win )
end

function tshow_( x::String; title = string(typeof( x )), showprogress=true, showkeyhelper=true )
    msgs = map( x->replace(x, "\t", "    "), split( x, "\n" ) )
    needy = length(msgs)
    needx = maximum( map( x->length(x), msgs ) )

    maxy= maxx= height= width= 0
    panel = nothing

    update_dimensions = ()-> begin
        (maxy, maxx) = getwinmaxyx( rootwin )
        height=max( 3, min( maxy-2, needy )+2 ) # including the borders
        width =max( 30, length(title)+2, min( maxx-4, needx )+4 ) # including the borders
    end

    update_dimensions()

    win = winnewcenter( height, width )
    panel = new_panel( win )

    currentTop = 1
    currentLeft = 1

    redrawviewer = ()->begin
        werase( win )
        box( win, 0, 0 )
        height, width = getwinmaxyx( win )
        npushed = 0
        for r in currentTop:min(currentTop+height-3, needy)
            s = string( SubString( msgs[ r ], currentLeft, currentLeft + width - 5 ) )
            mvwprintw( win, 1 + r-currentTop, 2, "%s",s )
            npushed += length(s)
            if npushed > 200
                refresh()
                wrefresh( win )
                #update_panels()
                #doupdate()
                npushed = 0
            end
        end
        if title != ""
            mvwprintw( win, 0, int( ( width - length(title) )/2 ), "%s", title )
        end
        if showprogress
            if needy <= height-2
                mvwprintw( win, 0, width-13, "%10s", "ALL" )
            else
                mvwprintw( win, 0, width-13, "%10s", @sprintf( "%9.2f%%", currentTop / (needy - height +2 ) * 100 ) )
            end
        end
        if showkeyhelper && (needy > height -2 || needx > width - 4)
            s = "F1: Help   Esc: exit"
            mvwprintw( win, height-1, int((width-length(s))/2), "%s", s )
        else
            s = "[Esc to continue]"
            mvwprintw( win, height-1, int((width-length(s))/2), "%s", s )
        end
        update_panels()
        doupdate()
    end

    redrawviewer()
    token = 0
    while( (token = readtoken()) != :esc )
        dorefresh = false
        if token == :up
            if currentTop > 1
                currentTop -= 1
                dorefresh = true
            else
                flash()
            end
        elseif token == :down
            if currentTop + height-2 < needy
                currentTop += 1
                dorefresh = true
            else
                flash()
            end
        elseif token == :left
            if currentLeft > 1
                currentLeft -= 1
                dorefresh = true
            else
                flash()
            end
        elseif token == :right
            if currentLeft + width-4 < needx
                currentLeft += 1
                dorefresh = true
            else
                flash()
            end
        elseif token == :pageup
            if currentTop > 1
                currentTop = max( 1, currentTop - (height-2) )
                dorefresh = true
            else
                flash()
            end
        elseif token == :pagedown
            if currentTop + height-2 < needy
                currentTop = min( needy - height + 2, currentTop + height - 2 )
                dorefresh = true
            else
                flash()
            end
        elseif  token == :home
            if currentTop != 1 || currentLeft != 1
                currentTop = 1
                currentLeft = 1
                dorefresh = true
            else
                flash()
            end
        elseif in( token, [ "<", "0", "g" ] )
            if currentTop != 1
                currentTop = 1
                dorefresh = true
            else
                flash()
            end
        elseif in( token, { ">", "G", symbol("end") } )
            if currentTop + height-2 < needy
                currentTop = needy - height+ 2
                dorefresh = true
            else
                flash()
            end
        elseif token == "L" # move half-way toward the end
            target = min( int(ceil((currentTop + needy - height+2)/2)), needy - height + 2 )
            if target != currentTop
                currentTop = target
                dorefresh = true
            else
                flash()
            end
        elseif token == "l" # move half-way toward the beginning
            target = max( int(floor( currentTop /2)), 1)
            if target != currentTop
                currentTop = target
                dorefresh = true
            else
                flash()
            end
        elseif token == :F1
            tshow_(
            """
PgUp/PgDn,
Arrow keys : standard navigation
l          : move halfway toward the start
L          : move halfway to the end
<,0,g      : jump to the start
>, G       : jump to the end
            """, title="Help", showprogress= false, showkeyhelper=false
            )
            dorefresh = true
        elseif token == :KEY_RESIZE || is_term_resized( maxy, maxx )
            update_dimensions()
            wresize( win, height, width )
            dorefresh = true
            #TODO search, jump to line, etc.
        end

        if dorefresh
            redrawviewer()
        end
    end
    del_panel( panel )
    delwin( win )
end

function winnewcenter( ysize, xsize )
    global rootwin
    (maxy, maxx) = getwinmaxyx( rootwin )
    local cols, lines, origx, origy
    if isa( ysize, Int )
        lines = ysize
    elseif isa( ysize, Float64 ) && 0.0 < ysize <= 1.0
        lines = int( maxy * ysize )
        if lines == 0
            throw( "lines are too small")
        end
    else
        throw( "illegal ysize " * string( ysize ) )
    end

    if isa( xsize, Int )
        cols = xsize
    elseif isa( xsize, Float64 ) && 0.0 < xsize <= 1.0
        cols = int( maxx * xsize )
        if cols == 0
            throw( "cols are too small")
        end
    else
        throw( "illegal xsize " * string( ysize ) )
    end

    origx = int( floor( (maxx-cols )/2 ) )
    origy = int( floor( (maxy-lines)/2 ) )
    win = newwin( lines, cols, origy, origx )
    cbreak()
    noecho()
    keypad( win, true )
    nodelay( win, false )
    notimeout( win, true )
    win
end

function tshow( x::Any )
    global callcount
    if callcount == 0
        initsession()
    end
    err = nothing
    callcount += 1
    #try
        tshow_( x )
    #catch er
        #err = er
    #end
    callcount -= 1
    if callcount == 0
        endsession()
    end
    if err != nothing
        println( err )
    end
end

function testkeydialog( remapkeypad::Bool = false )
    width = 25
    initsession()
    win = winnewcenter( 3, width )
    panel = new_panel( win )
    box( win, 0, 0 )
    title = "Key Test"
    keyhint = "[Esc to continue]"

    mvwprintw( win, 0, int( (width-length(title))/2), "%s", title )
    mvwprintw( win, 2, int( (width-length(keyhint))/2), "%s", keyhint )
    update_panels()
    doupdate()
    local token
    #while( (token = readtoken( remapkeypad )) != :esc )
    while( (token = readtoken( win )) != :esc )
        k = ""
        if isa( token, String )
            for c in token
                if isprint( c ) && isascii( c )
                    k *= string(c)
                else
                    k *= @sprintf( "{%x}", uint(c))
                end
            end
        elseif isa( token, Symbol )
            k = ":" * string(token)
        end
        k = k * repeat( " ", 21-length(k) )
        mvwprintw( win, 1, 2, "%s", k)
        update_panels()
        doupdate()
    end
    del_panel(panel)
    delwin( win )
    endsession()
end

end