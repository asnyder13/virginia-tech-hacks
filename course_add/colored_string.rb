class String
  def color(c)
    colors = {
      black:   30,
      red:     31,
      green:   32,
      yellow:  33,
      blue:    34,
      magenta: 35,
      cyan:    36,
      white:   37
    }
    return "\e[#{colors[c] || c}m#{self}\e[0m"
  end
end