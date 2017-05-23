require 'scraperwiki'
require 'mechanize'
require 'date'

agent = Mechanize.new

case ENV['MORPH_PERIOD']
  when 'thismonth'
    period = 'thismonth'
  when 'lastmonth'
    period = 'lastmonth'
  else
    period = 'thisweek'
end
puts "Getting data in `" + period + "`, changable via MORPH_PERIOD environment"

# Boroondara don't provide a search by date, so we have to use their fetch by
# last week and this week. Hopefully this is enough for the alerting service
url = "http://eservices.boroondara.vic.gov.au/EPlanning/Pages/XC.Track/SearchApplication.aspx?d=" + period + "&k=LodgementDate&t=PlnPermit,PlnPostPer"

# A general page (applicable to all applications) for downloading an "objections" form
COMMENT_URL = "mailto:boroondara@boroondara.vic.gov.au"

def extract_applications_from_page(page)
  applications = []
  links = page.links_with(:href => /SearchApplication.aspx\?id=\d+/)
  links.each do |link|
    app_page = link.click
    da = {:info_url => app_page.uri.to_s, :date_scraped => Date.today}
    da[:council_reference] = app_page.search('h1')[1].inner_text.strip.sub(/Reference number: /, "")
    da[:comment_url] = COMMENT_URL
    rows = app_page.search('.detail')
    rows.each do |row|
      label = row.at('.detailleft').inner_text.strip
      value = row.at('.detailright')
      case label
        when /properties/i
          da[:address] = value.at('a').inner_text.strip #site incorrectly repeats the same address
        when /submitted/i
          da[:date_received] = Date.parse(value.inner_text.strip, 'd/m/Y')
        when /description/i
          da[:description] = value.inner_text.strip.sub(/planning permit/i, "")
      end
    end
   applications << da
  end
  applications
end

applications = []

page = agent.get(url)
form = page.forms.first
page = form.submit(form.button_with(:name => /BtnAgree/)) # only needed for the first page

# get the first page of applications
applications += extract_applications_from_page(page)

# the paging is done via onlick javascript
next_links = page.search("//a[@onclick]")
next_links.each do |link|
  # for each onclick we extract the parameters and pass these in a GET request
  link.to_s.match /'pager','(\d+\|.*)'/
  link_mod = page.uri.to_s + "&__EVENTTARGET=pager&__EVENTARGUMENT=#{$1}"
  newpage = agent.get(link_mod)

  # and extract the applications from the newpage
  applications += extract_applications_from_page(newpage)
end

applications.each do |record|
  if (ScraperWiki.select("* from data where `council_reference`='#{record[:council_reference]}'").empty? rescue true)
    puts "Saving record " + record[:council_reference] + " - " + record[:address]
    ScraperWiki.save_sqlite([:council_reference], record)
  else
    puts "Skipping already saved record " + record[:council_reference]
  end
end
