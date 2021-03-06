#!/usr/bin/env ruby

require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'trollop'

$path = ARGV[0].to_s.scrub.gsub(' ', '_')

$opts = Trollop::options do
  opt :refresh, "force a redownload and refresh of the page", :short => 'f'
end

$man_path = "./"
$man_bin = "man"
$man_section = 1
$lang = "en"
$force_refresh = ($opts[:refresh] || false)
# Check if the manpage already exists in the man_path
# and if it doesn't then translate it to a wikipedia url,
# load the html, then convert and save to a manpage
if !File.exists?("#{$man_path}#{$path}.#{$man_section}") || $force_refresh
  # Open the page
  page = Nokogiri::HTML(open(URI.encode("http://#{$lang}.wikipedia.org/wiki/#{$path}")))
  # Get the page title
  $title = page.title.split('-').first.strip
  # Extract the main content of the page
  content = page.css('div#mw-content-text')[0]

  # Delete unneeded sections
  content.search('div.toc').remove                # Table of contents
  content.search('div.thumb').remove              # Thumbnails/images
  content.search('table.metadata').remove         # Metatables such as 'needs additional citations'
  content.search('table.vertical-navbox').remove  # Sideboxes
  content.search('span.mw-editsection').remove    # Edit marks
  refs = content.search('span#References')[0]     # Everything after and including references
  if refs
    refs = refs.parent # Span is in a <h2> element
    while refs.next
      refs.next.remove
    end
    refs.remove
  end

  # Replace links with their text, removing references
  content.search('a').each do |x|
    link = x.content
    link = "" if /\[.+\]/ =~ link
    x.replace(link)
  end

  # Delete empty <p> tags which Wikipedia seems to like
  content.search('p').each {|x| x.remove if x.children.empty?}

  # Format bold sections
  content.search('b').each do |x|
    x.content = "\\fB#{x.content}\\fR"
    x.replace(x.children)
  end

  # Format italic sections
  content.search('i').each do |x|
    x.content = "\\fI#{x.content}\\fR"
    x.replace(x.children)
  end

  # Format code sections
  content.search('div.mw-code').each do |x|
    code = x.search('pre').first
    code.content = ".PP\n.nf\n.RF\n#{x.content.strip}\n.RE\n.fi\n.PP\n"
    x.replace(code)
  end

  # Format equations
  # TODO - Groff *hates* LaTeX...
  content.search('img.tex').each do |x|
    # x.content = (Nokogiri::XML::Text.new(".nf\n___#{x['alt']}\n.fi\n", content))
  end

  # Format paragraphs
  content.search('p').each do |x|
    x.content = ".PP\n#{x.content.strip}\n.PP\n"
  end

  # Format section headers
  content.search('h2').each do |x|
    header = x.children[0].children[0]
    header.content = ".SH #{header.content.upcase}\n"
    x.replace(header)
  end


  # Format descripion lists
  content.search('dl').each do |x|
    text = ""
    x.children.each do |y|
      if y.name == "dt"
        text << ".TP\n#{y.content}\n"
      elsif y.name == "dd"
        text << "#{y.content}\n"
      end
    end
    x.replace(Nokogiri::XML::Text.new(text.strip, x))
  end

  # Format unordered lists
  content.search('ul').each do |x|
    text = ""
    x.search('li').each do |y|
      text << "\t#{y.content}\n"
    end
    x.replace(Nokogiri::XML::Text.new(text, x))
  end

  # Format tables
  content.search('table').each do |x|
    table = ".TS\nallbox;\n" # Surround with a box
    num_cols = nil
    x.search('tr').each do |row|
      unless num_cols
        # Look at the number of columns (if there are any)
        if !row.children.empty?
          cols = row.children.select{|y| y.name == 'td' || y.name == 'th'}
          # Use the colspan property if it exists
          # to determine the number of columns
          if cols.length > 0 && cols[0]['colspan']
            num_cols = cols[0]['colspan'].to_i
          else
            num_cols = cols.length
          end
        end
        table << "#{'l ' * num_cols}.\n"
      end
      # Form the rows
      row_text = ""
      row.children.each do |col|
        if col.name == 'td' || col.name == 'th'
          row_text << col.content.strip << "\t"
        end
      end
      table << "#{row_text.strip}\n"
    end
    table << ".TE\n"
    x.replace(Nokogiri::XML::Text.new(table, x))
  end

  # Reduce repeated newlines down to one
  content.content.gsub!(/\n+/, "\n")

  # Print to the man page
  File.open("#{$man_path}#{$path}.#{$man_section}", "w") do |f|
    f.puts ".TH \"#{$title.upcase}\" #{$man_section}"
    f.puts ".SH NAME\n#{$title} \- From Wikipedia, the free encyclopedia"
    f.puts ".SH DESCRIPTION"
    f.puts content.content
  end
end

# Load the manpage
exec("#{$man_bin}", *ARGV[1..-1], "-l", "#{$man_path}#{$path}.#{$man_section}")