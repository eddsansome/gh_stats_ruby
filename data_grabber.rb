require 'dotenv'
require 'net/http'
require 'json'
require 'time'
Dotenv.load

PullRequest = Struct.new(:number, :title, :merged_at, :created_at, :reviews) do 
	def unique_approvers
		reviewers = reviews.dig("edges")
		reviewers.select {|r| r.dig("node", "state") == "APPROVED" }
				 .map {|r| r.dig("node", "login") }
				 .count
	end

	def cycle_time
        created = Time.parse(created_at)
		merged = Time.parse(merged_at)
		((merged - created).to_f / 3600).round(2)
	end

	def csv_line
		"#{number},#{title},#{unique_approvers},#{Time.parse(created_at).to_date},#{Time.parse(merged_at).to_date},#{cycle_time}"
	end
end

class DataGrabber
  def self.call(...)
    new(...).call
  end

  def call
    @token = ENV["TOKEN"]

    pull_requests(nil, @prs)

    
  end

  def graphql_body(before)

	key = before.nil? ? "null" : "\"#{before}\""

   body =  <<~BODY
{ repository(owner: "smartpension", name: "api") {
	pullRequests(last: 100, states: MERGED, orderBy: {field: UPDATED_AT, direction: ASC}, before: #{key}) {
		pageInfo {
			startCursor
			hasNextPage
			endCursor
		}
			edges {
			  node {
				title
				url
				mergedAt
				createdAt
				number
				reviews(first: 100) {
				  edges {
					node {
					  state
					  author {
						login
					  }
					}
				  }
				}
			  }
			}
		  }
		}
	  }
    BODY

	{"query" => body}
  end

  def pull_requests(before, prs)
    req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
	req.body = JSON.generate(graphql_body(before))

	req['Content-Type'] = 'application/json'
	req['Authorization'] = "Bearer #{@token}"

	res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) {|http|
		http.request(req)
	  }

	  data = JSON.parse(res.body)

	  prs = data.dig("data", "repository", "pullRequests", "edges")
	  # PullRequest = Struct.new(:number, :title, :merged_at, :created_at, :reviewers)
	  derp = prs.map do |pr|
		raw_pr = pr.dig("node")
		p = PullRequest.new(raw_pr["number"], raw_pr["title"], raw_pr["mergedAt"], raw_pr["createdAt"], raw_pr["reviews"])
		p.csv_line
	  end

	  puts "number,title.gsub(",",""),approvers,created_at,merged_at,cycle_time(hours)"
	  puts derp

  end

  def uri
    URI('https://api.github.com/graphql')
  end

  def initialize
    @prs = []
  end
end

DataGrabber.call

