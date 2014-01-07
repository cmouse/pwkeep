require 'clipboard'

module PWKeep
  def self.run_editor(data, options) 
    ret = [false, data]

    Dispel::Screen.open do |screen|
      $ruco_screen = screen
      app = PWKeep::EditorApplication.new(data.to_s,
        :lines => screen.lines, :columns => screen.columns
      )

      screen.draw *app.display_info

      Dispel::Keyboard.output do |key|
        if key == :resize
          app.resize(screen.lines, screen.columns)
        else
          result = app.key key
          if result == :quit
            ret = [app.editor.saved_content != data, app.editor.saved_content]
            break
          end
        end

        screen.draw *app.display_info
      end
    end

    return ret
  end

  class EditorApplication
    attr_reader :editor, :status, :command, :options

    def initialize(data, options)
      @options = Ruco::OptionAccessor.new(options)
      @data = data

      setup_actions
      setup_keys
      create_components
    end

    def display_info
      [view, style_map, cursor]
    end

    def view
      [status.view, editor.view, command.view].join("\n")
    end

    def style_map
      status.style_map + editor.style_map + command.style_map
    end

    def cursor
      Ruco::Position.new(@focused.cursor.line + @status_lines, @focused.cursor.column)
    end

    # user typed a key
    def key(key)
      # deactivate select_mode if its not re-enabled in this action
      @select_mode_was_on = @select_mode
      @select_mode = false

      if bound = @bindings[key]
        return execute_action(bound)
      end

      case key

      # move
      when :down then move_with_select_mode :relative, 1,0
      when :right then move_with_select_mode :relative, 0,1
      when :up then move_with_select_mode :relative, -1,0
      when :left then move_with_select_mode :relative, 0,-1
      when :page_up then move_with_select_mode :page_up
      when :page_down then move_with_select_mode :page_down
      when :"Ctrl+right", :"Alt+f" then move_with_select_mode :jump, :right
      when :"Ctrl+left", :"Alt+b" then move_with_select_mode :jump, :left

      # select
      when :"Shift+down" then @focused.selecting { move(:relative, 1, 0) }
      when :"Shift+right" then @focused.selecting { move(:relative, 0, 1) }
      when :"Shift+up" then @focused.selecting { move(:relative, -1, 0) }
      when :"Shift+left" then @focused.selecting { move(:relative, 0, -1) }
      when :"Ctrl+Shift+left", :"Alt+Shift+left" then @focused.selecting{ move(:jump, :left) }
      when :"Ctrl+Shift+right", :"Alt+Shift+right" then @focused.selecting{ move(:jump, :right) }
      when :"Shift+end" then @focused.selecting{ move(:to_eol) }
      when :"Shift+home" then @focused.selecting{ move(:to_bol) }


      # modify
      when :tab then
        if @editor.selection
          @editor.indent
        else
          @focused.insert("\t")
        end
      when :"Shift+tab" then @editor.unindent
      when :enter then @focused.insert("\n")
      when :backspace then @focused.delete(-1)
      when :delete then @focused.delete(1)

      when :escape then # escape from focused
        @focused.reset
        @focused = editor
      else
        @focused.insert(key) if key.is_a?(String)
      end
    end

    def bind(key, action=nil, &block)
      raise "Ctrl+m cannot be bound" if key == :"Ctrl+m" # would shadow enter -> bad
      raise "Cannot bind an action and a block" if action and block
      @bindings[key] = action || block
    end

    def action(name, &block)
      @actions[name] = block
    end

    def ask(question, options={}, &block)
      @focused = command
      command.ask(question, options) do |response|
        @focused = editor
        block.call(response)
      end
    end

    def loop_ask(question, options={}, &block)
      ask(question, options) do |result|
        finished = (block.call(result) == :finished)
        loop_ask(question, options, &block) unless finished
      end
    end

    def configure(&block)
      instance_exec(&block)
    end

    def resize(lines, columns)
      @options[:lines] = lines
      @options[:columns] = columns
      create_components
      @editor.resize(editor_lines, columns)
    end

    private

    def setup_actions
      @actions = {}

      action :paste do
        @focused.insert(Clipboard.paste)
      end

      action :copy do
        Clipboard.copy(@focused.text_in_selection)
      end

      action :cut do
        Clipboard.copy(@focused.text_in_selection)
        @focused.delete(0)
      end

      action :save do
        result = editor.save
        if result != true
          ask("#{result.slice(0,100)} -- Enter=Retry Esc=Cancel "){ @actions[:save].call }
        end
      end

      action :quit do
        if editor.modified?
          ask("Lose changes? Enter=Yes Esc=Cancel") do
            editor.store_session
            :quit
          end
        else
          editor.store_session
          :quit
        end
      end

      action :go_to_line do
        ask('Go to Line: ') do |result|
          editor.move(:to_line, result.to_i - 1)
        end
      end

      action :delete_line do
        editor.delete_line
      end

      action :select_mode do
        @select_mode = !@select_mode_was_on
      end

      action :select_all do
        @focused.move(:to, 0, 0)
        @focused.selecting do
          move(:to, 9999, 9999)
        end
      end

      action :find do
        ask("Find: ", :cache => true) do |result|
          next if editor.find(result)

          if editor.content.include?(result)
            ask("No matches found -- Enter=First match ESC=Stop") do
              editor.move(:to, 0,0)
              editor.find(result)
            end
          else
            ask("No matches found in entire file", :auto_enter => true){}
          end
        end
      end

      action :find_and_replace do
        ask("Find: ", :cache => true) do |term|
          if editor.find(term)
            ask("Replace with: ", :cache => true) do |replace|
              loop_ask("Replace=Enter Skip=s All=a Cancel=Esc", :auto_enter => true) do |ok|
                case ok
                when '' # enter
                  editor.insert(replace)
                when 'a'
                  stop = true
                  editor.insert(replace)
                  editor.insert(replace) while editor.find(term)
                when 's' # do nothing
                else
                  stop = true
                end

                :finished if stop or not editor.find(term)
              end
            end
          end
        end
      end

      action(:undo){ @editor.undo if @focused == @editor }
      action(:redo){ @editor.redo if @focused == @editor }
      action(:move_line_up){ @editor.move_line(-1) if @focused == @editor }
      action(:move_line_down){ @editor.move_line(1) if @focused == @editor }

      action(:move_to_eol){ move_with_select_mode :to_eol }
      action(:move_to_bol){ move_with_select_mode :to_bol }

      action(:insert_hash_rocket){ @editor.insert(' => ') }
    end

    def setup_keys
      @bindings = {}
      bind :"Ctrl+s", :save
      bind :"Ctrl+w", :quit
      bind :"Ctrl+q", :quit
      bind :"Ctrl+g", :go_to_line
      bind :"Ctrl+f", :find
      bind :"Ctrl+r", :find_and_replace
      bind :"Ctrl+b", :select_mode
      bind :"Ctrl+a", :select_all
      bind :"Ctrl+d", :delete_line
      bind :"Ctrl+l", :insert_hash_rocket
      bind :"Ctrl+x", :cut
      bind :"Ctrl+c", :copy
      bind :"Ctrl+v", :paste
      bind :"Ctrl+z", :undo
      bind :"Ctrl+y", :redo
      bind :"Alt+Ctrl+down", :move_line_down
      bind :"Alt+Ctrl+up", :move_line_up
      bind :end, :move_to_eol
      bind :"Ctrl+e", :move_to_eol # for OsX
      bind :home, :move_to_bol
    end

    def load_user_config
      Ruco.application = self
      config = File.expand_path(@options[:rc] || "~/.ruco.rb")
      load config if File.exist?(config)
    end

    def create_components
      @status_lines = 1

      editor_options = @options.slice(
        :columns, :convert_tabs, :convert_newlines, :undo_stack_size, :color_theme
      ).merge(
        :window => @options.nested(:window),
        :history => @options.nested(:history),
        :lines => editor_lines
      ).merge(@options.nested(:editor))

      @editor ||= PWKeep::Editor.new(@data, editor_options)
      @status = PWKeep::StatusBar.new(@editor, @options.nested(:status_bar).merge(:columns => options[:columns]))
      @command = Ruco::CommandBar.new(@options.nested(:command_bar).merge(:columns => options[:columns]))
      command.cursor_line = editor_lines
      @focused = @editor
    end

    def editor_lines
      command_lines = 1
      @options[:lines] - @status_lines - command_lines
    end

    def parse_file_and_line(file)
      if file.to_s.include?(':') and not File.exist?(file)
        short_file, go_to_line = file.split(':',2)
        if File.exist?(short_file)
          file = short_file
        else
          go_to_line = nil
        end
      end
      [file, go_to_line]
    end

    def move_with_select_mode(*args)
      @select_mode = true if @select_mode_was_on
      if @select_mode
        @focused.selecting do
          move(*args)
        end
      else
        @focused.send(:move, *args)
      end
    end

    def execute_action(action)
      if action.is_a?(Symbol)
        @actions[action].call
      else
        action.call
      end
    end
  end

  class Editor
    attr_reader :file
    attr_reader :text_area
    attr_reader :history
    attr_reader :saved_content

    private :text_area
    delegate :view, :style_map, :cursor, :position,
      :insert, :indent, :unindent, :delete, :delete_line,
      :redo, :undo, :save_state,
      :selecting, :selection, :text_in_selection, :reset,
      :move, :resize, :move_line,
      :to => :text_area

    def initialize(data, options)
      @options = options

      content = data
      @options[:language] ||= LanguageSniffer.detect(@file, :content => content).language
      content.tabs_to_spaces! if @options[:convert_tabs]

      # cleanup newline formats
      @newline = content.match("\r\n|\r|\n")
      @newline = (@newline ? @newline[0] : "\n")
      content.gsub!(/\r\n?/,"\n")

      @saved_content = content
      @text_area = Ruco::EditorArea.new(content, @options)
      @history = @text_area.history
      restore_session
    end

    def find(text)
      move(:relative, 0,0) # reset selection
      start = text_area.content.index(text, text_area.index_for_position+1)
      return unless start

      # select the found word
      finish = start + text.size
      move(:to_index, finish)
      selecting{ move(:to_index, start) }

      true
    end

    def modified?
      @saved_content != text_area.content
    end

    def save
      lines = text_area.send(:lines)
      lines.each(&:rstrip!) if @options[:remove_trailing_whitespace_on_save]
      lines << '' if @options[:blank_line_before_eof_on_save] and lines.last.to_s !~ /^\s*$/
      content = lines * @newline

      @saved_content = content.gsub(/\r?\n/, "\n")

      true
    rescue Object => e
      e.message
    end

    def store_session
    end

    def content
      text_area.content.freeze # no modifications allowed
    end

    private

    def restore_session
    end

    def session_store
    end
  end

  class StatusBar
    def initialize(editor, options)
      @editor = editor
      @options = options
    end

    def view
      columns = @options[:columns]

      version = "Ruco #{Ruco::VERSION} -- "
      position = " #{@editor.position.line + 1}:#{@editor.position.column + 1}"
      indicators = "#{change_indicator}#{writable_indicator}"
      essential = version + position + indicators
      space_left = [columns - essential.size, 0].max

      # fit file name into remaining space
      "#{version}#{indicators}#{' ' * space_left}#{position}"[0, columns]
    end

    def style_map
      Dispel::StyleMap.single_line_reversed(@options[:columns])
    end

    def change_indicator
      @editor.modified? ? '*' : ' '
    end

    def writable_indicator
      true
    end

    private

    # fill the line with left column and then overwrite the right section
    def spread(left, right)
      empty = [@options[:columns] - left.size, 0].max
      line = left + (" " * empty)
      line[(@options[:columns] - right.size - 1)..-1] = ' ' + right
      line
    end
  end
end
