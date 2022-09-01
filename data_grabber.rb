# frozen_string_literal: true

require 'dotenv'
require 'net/http'
require 'json'
require 'time'
Dotenv.load

PullRequest = Struct.new(:number, :title, :merged_at, :created_at, :reviews) do
  def unique_approvers
    reviewers = reviews['edges']
    reviewers.select { |r| r.dig('node', 'state') == 'APPROVED' }
             .map { |r| r.dig('node', 'login') }
             .count
  end

  def cycle_time
    ((merged_at - created_at).to_f / 3600).round(2)
  end

  def csv_line
    "#{number},#{title.gsub(',', '')},#{unique_approvers},#{created_at.to_date},#{merged_at.to_date},#{cycle_time}"
  end
end

class DataGrabber
  def self.call(...)
    new(...).call
  end

  def call
    @token = ENV.fetch('TOKEN', nil)

    prs = pull_requests(nil, [])

    puts 'number,title,approvers,created_at,merged_at,cycle_time(hours)'
    prs.sort_by { |pr| pr.merged_at.to_datetime }
       .each do |pr|
      puts pr.csv_line if pr.merged_at.to_date >= Date.new(2022, 8, 1) && pr.merged_at.to_date < Date.new(2022, 9, 1)
    end
  end

  def graphql_body(before)
    key = before.nil? ? 'null' : "\"#{before}\""

    body = <<~BODY
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

    { 'query' => body }
  end

  def pull_requests(before, prs)
    sleep 2

    # guard clause
    return prs if prs.size.positive? && prs.last.merged_at.to_date < Date.new(2022, 8, 1)

    req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
    req.body = JSON.generate(graphql_body(before))

    req['Content-Type'] = 'application/json'
    req['Authorization'] = "Bearer #{@token}"

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    data = JSON.parse(res.body)

    pr_data = data.dig('data', 'repository', 'pullRequests', 'edges')

    # PullRequest = Struct.new(:number, :title, :merged_at, :created_at, :reviewers)
    pr_data.each do |pr|
      raw_pr = pr['node']
      prs << PullRequest.new(raw_pr['number'], raw_pr['title'], Time.parse(raw_pr['mergedAt']),
                             Time.parse(raw_pr['createdAt']), raw_pr['reviews'])
    end

    pull_requests(data.dig('data', 'repository', 'pullRequests', 'pageInfo', 'startCursor'), prs)
  end

  def uri
    URI('https://api.github.com/graphql')
  end

  def initialize
    @prs = []
  end
end

DataGrabber.call
