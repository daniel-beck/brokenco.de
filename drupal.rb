require 'rubygems'
require 'sequel'
require 'fileutils'
require 'yaml'

# NOTE: This converter requires Sequel and the MySQL gems.
# The MySQL gem can be difficult to install on OS X. Once you have MySQL
# installed, running the following commands should work:
# $ sudo gem install sequel
# $ sudo gem install mysql -- --with-mysql-config=/usr/local/mysql/bin/mysql_config

module Jekyll
  module Drupal
    # Reads a MySQL database via Sequel and creates a post file for each post
    # in wp_posts that has post_status = 'publish'. This restriction is made
    # because 'draft' posts are not guaranteed to have valid dates.
    QUERY = "SELECT node.nid, \
                    node.title, \
                    node_revisions.body, \
                    node.created, \
                    node.status, \
                    node_revisions.format, \
                    filter_formats.name format_name\
             FROM node, \
                  node_revisions, \
                  filter_formats \
             WHERE (node.type = 'blog' OR node.type = 'story') AND \
                  (node_revisions.format = filter_formats.format) \
             AND node.vid = node_revisions.vid"

    def self.process(dbname, user, pass, host = 'localhost')
      db = Sequel.mysql(dbname, :user => user, :password => pass, :host => host, :encoding => 'utf8')

      FileUtils.mkdir_p "_posts"
      FileUtils.mkdir_p "_drafts"

      # Create the refresh layout
      # Change the refresh url if you customized your permalink config
      File.open("_layouts/refresh.html", "w") do |f|
        f.puts <<EOF
<!DOCTYPE html>
<html>
<head>
<meta http-equiv="content-type" content="text/html; charset=utf-8" />
<meta http-equiv="refresh" content="0;url={{ page.refresh_to_post_id }}.html" />
</head>
</html>
EOF
      end

      db[QUERY].each do |post|
        # Get required fields and construct Jekyll compatible name
        node_id = post[:nid]
        title = post[:title]
        content = post[:body]
        created = post[:created]
        time = Time.at(created)
        is_published = post[:status] == 1
        dir = is_published ? "_posts" : "_drafts"
        slug = title.strip.downcase.gsub(/(&|&amp;)/, ' and ').gsub(/[\s\.\/\\]/, '-').gsub(/[^\w-]/, '').gsub(/[-_]{2,}/, '-').gsub(/^[-_]/, '').gsub(/[-_]$/, '')
        format_name = post[:format_name]
        puts title
        if format_name.downcase == "markdown"
          format = "markdown"
        else
          format = "html"
          if format_name.downcase == "filtered html" or format_name.downcase == "full html"
            process_filtered_html!(content)
          end
        end

        name = time.strftime("%Y-%m-%d-") + slug + ".#{format}"
        tags = []
        tags_query = "SELECT name FROM term_data WHERE tid IN \
                      (SELECT tid FROM term_node WHERE nid = #{node_id})"
        db[tags_query].each do |row|
          tags << row[:name].downcase.strip
        end
        # Get the relevant fields as a hash, delete empty fields and convert
        # to YAML for the header
        data = {
           'layout' => 'post',
           'title' => title.to_s,
           'nodeid' => node_id,
           'created' => created,
           'tags' => tags,
         }.delete_if { |k,v| v.nil? || v == ''}.to_yaml

        # Write out the data and content to file
        File.open("#{dir}/#{name}", "w") do |f|
          f.puts data
          f.puts "---"
          f.puts content
        end

        # Make a file to redirect from the old Drupal URL
        if is_published
          FileUtils.mkdir_p "node/#{node_id}"
          File.open("node/#{node_id}/index.md", "w") do |f|
            f.puts "---"
            f.puts "layout: refresh"
            f.puts "refresh_to_post_id: /#{time.strftime("%Y/%m/%d/") + slug}"
            f.puts "---"
          end

          path_query = "SELECT src, dst FROM url_alias WHERE src = 'node/#{node_id}'"
          db[path_query].each do |row|
            puts "Write alias for #{node_id} => #{row[:dst]}"
            FileUtils.mkdir_p(row[:dst])

            File.open("#{row[:dst]}/index.md", "w") do |f|
              f.puts "---"
              f.puts "layout: refresh"
              f.puts "refresh_to_post_id: /#{time.strftime("%Y/%m/%d/") + slug}"
              f.puts "---"
            end
          end
        end
      end

      # TODO: Make dirs & files for nodes of type 'page'
        # Make refresh pages for these as well
      # TODO: Make refresh dirs & files according to entries in url_alias table
    end

    def self.process_filtered_html!(content)
      content.gsub!(/\n/, "<br>\n")
    end

    def self.process_source_tags!(content)
      content.gsub!(/<lisp>/, "{% highlight cl %}")
      content.gsub!(/<\/lisp>/, "{% endhighlight %}")
      content.gsub!(/<bash>/, "{% highlight bash %}")
      content.gsub!(/<\/bash>/, "{% endhighlight %}")
      content.gsub!(/<code language="java5">/, "{% highlight java %}")
      # TODO content.gsub!(/<\/code>/, "{% endhighlight %}")
      content.gsub!(/<code language="java">/, "{% highlight java %}")
      # TODO content.gsub!(/<\/code>/, "{% endhighlight %}")
      content.gsub!(/<python>/, "{% highlight python %}")
      content.gsub!(/<\/python>/, "{% endhighlight %}")
    end
  end
end

Jekyll::Drupal.process('ub', 'root', '', '127.0.0.1')
