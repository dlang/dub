/**
 * Authors: ponce
 * Date: July 28, 2014
 * License: Licensed under the MIT license. See LICENSE for more information
 * Version: 1.0.2
 */
module dub.internal.colorize.winterm;

version(Windows)
{
  import core.sys.windows.windows;

  // Patch for DMD 2.065 compatibility
  static if( __VERSION__ < 2066 ) private enum nogc = 1;

  // This is a state machine to enable terminal colors on Windows.
  // Parses and interpret ANSI/VT100 Terminal Control Escape Sequences.
  // Only supports colour sequences, will output char incorrectly on invalid input.
  struct WinTermEmulation
  {
  public:
    @nogc void initialize() nothrow
    {
      // saves console attributes
      _console = GetStdHandle(STD_OUTPUT_HANDLE);
      _savedInitialColor = (0 != GetConsoleScreenBufferInfo(_console, &consoleInfo));
      _state = State.initial;
    }

    @nogc ~this() nothrow
    {
      // Restore initial text attributes on release
      if (_savedInitialColor)
      {
        SetConsoleTextAttribute(_console, consoleInfo.wAttributes);
        _savedInitialColor = false;
      }
    }

    enum CharAction
    {
      write,
      drop,
      flush
    }

    // Eat one character and update color state accordingly.
    // Returns what to do with the fed character.
    @nogc CharAction feed(dchar d) nothrow
    {
      final switch(_state) with (State)
      {
        case initial:
          if (d == '\x1B')
          {
            _state = escaped;
            return CharAction.flush;
          }
          break;

        case escaped:
          if (d == '[')
          {
            _state = readingAttribute;
            _parsedAttr = 0;
            return CharAction.drop;
          }
          break;


        case readingAttribute:
          if (d >= '0' && d <= '9')
          {
            _parsedAttr = _parsedAttr * 10 + (d - '0');
            return CharAction.drop;
          }
          else if (d == ';')
          {
            executeAttribute(_parsedAttr);
            _parsedAttr = 0;
            return CharAction.drop;
          }
          else if (d == 'm')
          {
            executeAttribute(_parsedAttr);
            _state = State.initial;
            return CharAction.drop;
          }
          break;
      }
      return CharAction.write;
    }

  private:
    HANDLE _console;
    bool _savedInitialColor;
    CONSOLE_SCREEN_BUFFER_INFO consoleInfo;
    State _state;
    WORD _currentAttr;
    int _parsedAttr;

    enum State
    {
      initial,
      escaped,
      readingAttribute
    }

    @nogc void setForegroundColor(WORD fgFlags) nothrow
    {
      _currentAttr = _currentAttr & ~(FOREGROUND_BLUE | FOREGROUND_GREEN | FOREGROUND_RED | FOREGROUND_INTENSITY);
      _currentAttr = _currentAttr | fgFlags;
      SetConsoleTextAttribute(_console, _currentAttr);
    }

    @nogc void setBackgroundColor(WORD bgFlags) nothrow
    {
      _currentAttr = _currentAttr & ~(BACKGROUND_BLUE | BACKGROUND_GREEN | BACKGROUND_RED | BACKGROUND_INTENSITY);
      _currentAttr = _currentAttr | bgFlags;
      SetConsoleTextAttribute(_console, _currentAttr);
    }

    // resets to the same foreground color that was set on initialize()
    @nogc void resetForegroundColor() nothrow
    {
      if (!_savedInitialColor)
        return;

      _currentAttr = _currentAttr & ~(FOREGROUND_BLUE | FOREGROUND_GREEN | FOREGROUND_RED | FOREGROUND_INTENSITY);
      _currentAttr = _currentAttr | (consoleInfo.wAttributes & (FOREGROUND_BLUE | FOREGROUND_GREEN | FOREGROUND_RED | FOREGROUND_INTENSITY));
      SetConsoleTextAttribute(_console, _currentAttr);
    }

    // resets to the same background color that was set on initialize()
    @nogc void resetBackgroundColor() nothrow
    {
      if (!_savedInitialColor)
        return;

      _currentAttr = _currentAttr & ~(BACKGROUND_BLUE | BACKGROUND_GREEN | BACKGROUND_RED | BACKGROUND_INTENSITY);
      _currentAttr = _currentAttr | (consoleInfo.wAttributes & (BACKGROUND_BLUE | BACKGROUND_GREEN | BACKGROUND_RED | BACKGROUND_INTENSITY));
      SetConsoleTextAttribute(_console, _currentAttr);
    }

    @nogc void executeAttribute(int attr) nothrow
    {
      switch (attr)
      {
        case 0:
          // reset all attributes
          SetConsoleTextAttribute(_console, consoleInfo.wAttributes);
          break;

        default:
          if ( (30 <= attr && attr <= 37) || (90 <= attr && attr <= 97) )
          {
            WORD color = 0;
            if (90 <= attr && attr <= 97)
            {
              color = FOREGROUND_INTENSITY;
              attr -= 60;
            }
            attr -= 30;
            color |= (attr & 1 ? FOREGROUND_RED : 0) | (attr & 2 ? FOREGROUND_GREEN : 0) | (attr & 4 ? FOREGROUND_BLUE : 0);
            setForegroundColor(color);
          }
          else if (attr == 39) // fg.init
          {
            resetForegroundColor();
          }

          if ( (40 <= attr && attr <= 47) || (100 <= attr && attr <= 107) )
          {
            WORD color = 0;
            if (100 <= attr && attr <= 107)
            {
              color = BACKGROUND_INTENSITY;
              attr -= 60;
            }
            attr -= 40;
            color |= (attr & 1 ? BACKGROUND_RED : 0) | (attr & 2 ? BACKGROUND_GREEN : 0) | (attr & 4 ? BACKGROUND_BLUE : 0);
            setBackgroundColor(color);
          }
          else if (attr == 49) // bg.init
          {
            resetBackgroundColor();
          }
      }
    }
  }
}
