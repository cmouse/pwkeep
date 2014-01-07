module PWKeep

class EditorApplication
  attr_reader :editor, :status, :command, :options 

  def initialize(data,options={})
    @data = data
    @options = Ruco::OptionAccessor.new(options)
    setup_actions
    setup_keys
    create_components
  end

  def content 
    editor.save
  end

  def display_info
    [view, style_map, cursor]
  end

  def view
    [editor.view].join("\n")
  end

  def style_map
    editor.style_map
  end

  def cursor
    Ruco::Position.new(@editor.cursor.line, @editor.cursor.column)
  end

  # user typed a key
  def key(key)
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

    when :enter then @editor.insert("\n")
    when :backspace then @editor.delete(-1)
    when :delete then @editor.delete(1)

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
    @editor = command
    command.ask(question, options) do |response|
      @editor = editor
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

    action :delete_line do
      editor.delete_line
    end

    action(:undo){ @editor.undo if @editor == @editor }
    action(:redo){ @editor.redo if @editor == @editor }
    action(:move_line_up){ @editor.move_line(-1) if @editor == @editor }
    action(:move_line_down){ @editor.move_line(1) if @editor == @editor }

    action(:move_to_eol){ move_with_select_mode :to_eol }
    action(:move_to_bol){ move_with_select_mode :to_bol }

  end

  def setup_keys
    @bindings = {}
    bind :"Ctrl+s", :save
    bind :"Ctrl+w", :quit
    bind :"Ctrl+q", :quit
    bind :"Ctrl+g", :go_to_line
    bind :"Ctrl+d", :delete_line
    bind :end, :move_to_eol
    bind :"Ctrl+e", :move_to_eol # for OsX
    bind :home, :move_to_bol
  end

  def create_components
      editor_options = @options.slice(
        :columns, :convert_tabs, :convert_newlines, :undo_stack_size, :color_theme
      ).merge(
        :window => @options.nested(:window),
        :history => @options.nested(:history),
        :lines => editor_lines
      ).merge(@options.nested(:editor))
    @editor ||= PWKeep::Editor.new(@data, editor_options)
  end

  def editor_lines
    @options[:lines]
  end

  def move_with_select_mode(*args)
    @editor.send(:move, *args)
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

  private :text_area

  delegate :view, :style_map, :cursor, :position,
    :insert, :indent, :unindent, :delete, :delete_line,
    :save_state, :store_session, :content, 
    :reset,
    :move, :resize, :move_line,
    :to => :text_area

  def initialize(content, options)
    @options = options

    # cleanup newline formats
    @newline = content.match("\r\n|\r|\n")
    @newline = (@newline ? @newline[0] : "\n")
    content.gsub!(/\r\n?/,"\n")

    @saved_content = content
    @text_area = EditorArea.new(content, @options)
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
  end

  def store_session
    @saved_content = content
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

class EditorArea < Ruco::TextArea
  include Ruco::Editor::LineNumbers
  include Ruco::Editor::History

  def delete_line
    lines.slice!(line, 1)
    sanitize_position
  end

  def move_line(direction)
    old = line
    new = line + direction
    return if new < 0
    return if new >= lines.size
    lines[old].leading_whitespace = lines[new].leading_whitespace
    lines[old], lines[new] = lines[new], lines[old]
    @line += direction
  end

  def indent
    selected_lines.each do |line|
      lines[line].insert(0, ' ' * Ruco::TAB_SIZE)
    end
    adjust_to_indentation Ruco::TAB_SIZE
  end

  def unindent
    lines_to_unindent = (selection ? selected_lines : [line])
    removed = lines_to_unindent.map do |line|
      remove = [lines[line].leading_whitespace.size, Ruco::TAB_SIZE].min
      lines[line].slice!(0, remove)
      remove
    end

    adjust_to_indentation -removed.first, -removed.last
  end

  def state
    {
      :content => content,
      :position => position,
      :screen_position => screen_position
    }
  end

  def state=(data)
    @selection = nil
    @lines = data[:content].naive_split("\n") if data[:content]
    self.position = data[:position]
    self.screen_position = data[:screen_position]
  end

  # TODO use this instead of instance variables
  def screen_position
    Ruco::Position.new(@window.top, @window.left)
  end

  def screen_position=(pos)
    @window.set_top(pos[0], @lines.size)
    @window.left = pos[1]
  end

  def adjust_to_indentation(first, last=nil)
    last ||= first
    if selection
      cursor_adjustment = (selection.first == position ? first : last)
      selection.first.column = [selection.first.column + first, 0].max
      selection.last.column = [selection.last.column + last, 0].max
      self.column += cursor_adjustment
    else
      self.column += first
    end
  end

  def selected_lines
    selection.first.line.upto(selection.last.line)
  end
end

end
