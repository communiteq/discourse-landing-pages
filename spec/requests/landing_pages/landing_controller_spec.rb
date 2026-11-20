# frozen_string_literal: true

describe LandingPages::LandingController do
  fab!(:admin_user, :admin)
  fab!(:theme)

  before do
    LandingPages::Page.create({ name: "Public", path: "public", body: "body" })
    LandingPages::Page.create({ name: "Private", path: "private", group_ids: [1], body: "body" })
  end

  after do
    LandingPages::Page.find_by(:path, "public").destroy
    LandingPages::Page.find_by(:path, "private").destroy
  end

  it "shows a public page" do
    get "/public"
    expect(response.status).to eq(200)
  end

  it "shows a private page if its group restrictions are met" do
    sign_in(admin_user)
    get "/private"
    expect(response.status).to eq(200)
  end

  it "forbids access to a private page if its group restrictions are not met" do
    get "/private"
    expect(response.status).to eq(403)
  end

  it "sends back a json representation of the page" do
    get "/public.json"
    expect(response.status).to eq(200)
    expect(response.parsed_body["page"]["body"]).to eq("body")
  end

  it "shows the normal page if the user agent is a bot even if redirect to Home Page TC is set" do
    SiteSetting.landing_redirect_to_homepages = true
    get "/public", headers: { "HTTP_USER_AGENT" => "Googlebot" }
    expect(response.status).to eq(200)
    expect(response.parsed_body.at("body").content.strip).to eq("body")
  end

  it "shows the normal page if redirect to Home Page TC is set to false" do
    SiteSetting.landing_redirect_to_homepages = false
    get "/public"
    expect(response.status).to eq(200)
    expect(response.parsed_body.at("body").content.strip).to eq("body")
  end

  it "renders the core and selected theme styles for a themed landing page" do
    theme.set_field(target: :common, name: :scss, value: ".landing-page { color: red; }")
    theme.set_field(target: :desktop, name: :scss, value: ".landing-page { color: blue; }")
    theme.set_field(target: :mobile, name: :scss, value: ".landing-page { color: green; }")
    theme.save!
    page = LandingPages::Page.find_by(:path, "public")
    page.theme_id = theme.id
    page.save

    get "/public"

    expect(response.status).to eq(200)
    stylesheets = response.parsed_body.css('link[rel="stylesheet"]').map { |link| link["href"] }
    expect(stylesheets).to include(a_string_matching(%r{/stylesheets/common_}))
    expect(stylesheets).to include(a_string_matching(%r{/stylesheets/common_theme_}))
    expect(stylesheets).to include(a_string_matching(%r{/stylesheets/desktop_theme_}))

    get "/public",
        headers: {
          "HTTP_USER_AGENT" =>
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
        }

    expect(response.status).to eq(200)
    stylesheets = response.parsed_body.css('link[rel="stylesheet"]').map { |link| link["href"] }
    expect(stylesheets).to include(a_string_matching(%r{/stylesheets/common_}))
    expect(stylesheets).to include(a_string_matching(%r{/stylesheets/mobile_theme_}))
  end

  context "with Content Security Policy enabled" do
    before do
      SiteSetting.content_security_policy = true
      LandingPages::Global.new(scripts: ["https://example.com/custom.js"]).save
    end

    after { LandingPages::Global.destroy }

    it "uses one response nonce for every generated script for an anonymous request" do
      get "/public"

      expect_script_nonces_to_match_policy
    end

    it "uses one response nonce for every generated script for a logged-in request" do
      sign_in(admin_user)

      get "/public"

      expect_script_nonces_to_match_policy
    end

    it "includes the corrected mobile JavaScript path" do
      get "/public",
          headers: {
            "HTTP_USER_AGENT" =>
              "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
          }

      scripts = response.parsed_body.css("script[src]")
      expect(scripts.map { |script| script["src"] }).to include(
        "/plugins/discourse-landing-pages/javascripts/mobile.js",
      )
      expect_script_nonces_to_match_policy
    end

    def expect_script_nonces_to_match_policy
      expect(response.status).to eq(200)

      policy = response.headers["Content-Security-Policy"]
      nonce = policy&.match(/'nonce-([^']+)'/)&.captures&.first
      expect(nonce).to be_present

      expected_sources = [
        "https://ajax.googleapis.com/ajax/libs/jquery/3.6.0/jquery.min.js",
        "https://example.com/custom.js",
        "/plugins/discourse-landing-pages/javascripts/common.js",
      ]
      scripts = response.parsed_body.css("script[src]")

      expected_sources.each do |source|
        script = scripts.find { |node| node["src"] == source }
        expect(script).to be_present, "expected a script tag for #{source}"
        expect(script["nonce"]).to eq(nonce)
      end

      device_script =
        scripts.find do |node|
          node["src"]&.match?(%r{/plugins/discourse-landing-pages/javascripts/(mobile|desktop)\.js})
        end
      expect(device_script).to be_present
      expect(device_script["nonce"]).to eq(nonce)
    end
  end
end
