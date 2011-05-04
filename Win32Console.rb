# Hacked up win32 Console Library
# has only the functions I need
# use at your own peril!

# most of this is taken fomr the mswin32_console package
# http://rubyforge.org/projects/win32console/
# Thanks Gonzalo Garramuno & Michael L. Semon
#
#
# Copyright (C) 2010 Nik Zions (nik@nikspace.net)
# You may license this software under the Ruby License
# http://www.ruby-lang.org/en/LICENSE.txt
#
# Original Win32_Console was:
# Copyright (C) 2003 Gonzalo Garramuno (ggarramuno@aol.com)
#
# Original Win32API_Console was:
# Copyright (C) 2001 Michael L. Semon (mlsemon@sega.net)
#
#
# Version 1.0   Original
# Version 1.1   Added Screen Element Class
# Version 1.2   Fixed bug with ScreenElement::_write
#               Had Win32Console::setPosition x&y reversed
# Version 1.3   Added getColor
#               Added int2Color
#               Fixed ScreenElement::_write to use colors
# Version 1.3a  Clarified Licensing
# Version 1.3b  Fixed Stupid bug with math in Win32Console::getColors (not multiplying by 16 for fgc subtraction)
# Version 1.4   Added Class Mutex to ScreenElement
#               ScreenElement::_write is now thread safe
# Version 1.5   Fixed bug with box size trimming in ScreenElement::_write
#

require 'Win32API'
require 'thread'


class Win32Console
  def color2int(c)
    unless @colormap
      @colormap = Hash.new
      @colormap["black"] = 0
      @colormap["blue"] = 1
      @colormap["green"] = 2
      @colormap["cyan"] = 3
      @colormap["red"] = 4
      @colormap["magenta"] = 5
      @colormap["yellow"] = 6
      @colormap["white"] = 7
      @colormap["gray"] = 8
      @colormap["bright_blue"] = 9
      @colormap["bright_green"] = 10
      @colormap["bright_cyan"] = 11
      @colormap["bright_red"] = 12
      @colormap["bright_magenta"] = 13
      @colormap["bright_yellow"] = 14
      @colormap["bright_white"] = 15
    end
    return @colormap[c] if @colormap[c]
    # default to black
    return 0
  end

  def int2color(i)
    unless @cintmap
      @cintmap = Array.new
      @cintmap << "black"
      @cintmap << "blue"
      @cintmap << "green"
      @cintmap << "cyan"
      @cintmap << "red"
      @cintmap << "magenta"
      @cintmap << "yellow"
      @cintmap << "white"
      @cintmap << "gray"
      @cintmap << "bright_blue"
      @cintmap << "bright_green"
      @cintmap << "bright_cyan"
      @cintmap << "bright_red"
      @cintmap << "bright_magenta"
      @cintmap << "bright_yellow"
      @cintmap << "bright_white"
    end
    return @cintmap[i] if @cintmap[i]
    return nil
  end

  def initialize()
    #    grab STDOUT
    #    STD_INPUT_HANDLE          = 0xFFFFFFF6
    #    STD_OUTPUT_HANDLE         = 0xFFFFFFF5
    #    STD_ERROR_HANDLE          = 0xFFFFFFF4
    @handle = Win32API.new( "kernel32", "GetStdHandle", ['l'], 'l' ).call(0xFFFFFFF5)
  end

  def clear
    system('cls')
    setPosition(0,0)
  end

  def setPosition(x=0,y=0)
    wapi = Win32API.new( "kernel32", "SetConsoleCursorPosition", ['l', 'p'], 'l' )
    wapi.call(@handle, (y << 16) + x)
  end

  def getPosition
    ary = getInfoRaw
    ret = Array.new()
    ret << ary[2].to_i
    ret << ary[3].to_i
    return ret
  end

  def getSize
    ary = getInfoRaw
    return ary[0].to_i,ary[1].to_i
  end

  def getInfo
    ret = Array.new()
    ary = getInfoRaw

    ret << "cols:#{ary[0]}"
    ret << "rows:#{ary[1]}"
    ret << "current_col:#{ary[2]}"
    ret << "current_row:#{ary[3]}"
    ret << "attributes:#{ary[4]}"
    ret << "leftcol:#{ary[5]}"
    ret << "toprow:#{ary[6]}"
    ret << "rightcol:#{ary[7]}"
    ret << "botrow:#{ary[8]}"
    ret << "maxcols:#{ary[9]}"
    ret << "maxrows:#{ary[10]}"
    return ret
  end

  def getInfoRaw
    wapi = Win32API.new( "kernel32", "GetConsoleScreenBufferInfo", ['l', 'p'], 'l' )
    lpBuffer = ' ' * 22
    wapi.call( @handle, lpBuffer)
    return lpBuffer.unpack('SSSSSssssSS')
  end

  def getAtt
    ary = getInfoRaw
    return ary[4].to_i
  end

  def setAtt(att=7)
    wapi = Win32API.new( "kernel32", "SetConsoleTextAttribute", ['l', 'i'], 'l' )
    wapi.call(@handle,att)
  end

  def getColors()
    att = getAtt()
    bgc = att / 16
    fgc = att - (bgc * 16)
    return([int2color(fgc),int2color(bgc)])
  end

  def setColor(fg="white",bg="black")
    fg.downcase!
    bg.downcase!
    att = color2int(fg) + ( color2int(bg) * 16 )
    setAtt(att)
  end

  def setTitle(t)
    Win32API.new( "kernel32", "SetConsoleTitle",['p'], 'l' ).call(t)
  end

  def getTitle
    wapi = Win32API.new( "kernel32", "GetConsoleTitle", ['p', 'l'], 'l' )
    nSize = 120
    lpConsoleTitle = ' ' * nSize
    wapi.call( lpConsoleTitle, nSize )
    return lpConsoleTitle.strip
  end
end

class ScreenElement
  attr_accessor :xPos, :yPos, :fgColor, :bgColor, :size
  attr_reader :value
  @@mtx = Mutex.new()
  def initialize(c,v,x=0,y=0,fgc="white",bgc="black",s=20)
    @xPos = x
    @yPos = y
    @fgColor = fgc
    @bgColor = bgc
    @value = v
    @size = s
    @aSize = (s - 1)
    @con = c

    _write()
  end

  def value=(v)
    @value = v
    _write
  end

  def _write()
    # lock the screen
    @@mtx.lock()

    # save current position and colors
    cx,cy = @con.getPosition()
    fc,bc = @con.getColors()

    # write it out
    @con.setPosition(@xPos,@yPos)
    @con.setColor(@fgColor,@bgColor)
    print @value[0..@aSize].ljust(@aSize)

    # set old position and colors
    @con.setPosition(cx,cy)
    @con.setColor(fc,bc)

    # now unlock the screen
    @@mtx.unlock()
  end
end