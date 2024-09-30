describe package("exim4") do
  it { should be_installed }
end

describe service("exim4") do
  it { should be_enabled }
  it { should be_running }
end

describe port(25) do
  it { should be_listening }
  its("protocols") { should cmp %w[tcp tcp6] }
end
