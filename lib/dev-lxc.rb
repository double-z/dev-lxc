require "fileutils"
require "digest/sha1"
require "lxc"
require "dev-lxc/container"
require "dev-lxc/chef-server"
require "dev-lxc/chef-cluster"

module DevLXC
  def self.create_base_platform(base_platform_name)
    base_platform = DevLXC::Container.new(base_platform_name)
    if base_platform.defined?
      puts "Using existing container #{base_platform.name}"
      return base_platform
    end
    puts "Creating container #{base_platform.name}"
    case base_platform.name
    when "b-ubuntu-1004"
      base_platform.create("download", "btrfs", 0, ["-d", "ubuntu", "-r", "lucid", "-a", "amd64"])
    when "b-ubuntu-1204"
      base_platform.create("download", "btrfs", 0, ["-d", "ubuntu", "-r", "precise", "-a", "amd64"])
    when "b-centos-5"
      base_platform.create("centos", "btrfs", 0, ["-R", "5"])
    when "b-centos-6"
      base_platform.create("download", "btrfs", 0, ["-d", "centos", "-r", "6", "-a", "amd64"])
    end
    hwaddr = '00:16:3e:' + Digest::SHA1.hexdigest(Time.now.to_s).slice(0..5).unpack('a2a2a2').join(':')
    puts "Setting #{base_platform.name} container's lxc.network.0.hwaddr to #{hwaddr}"
    base_platform.set_config_item("lxc.network.0.hwaddr", hwaddr)
    base_platform.save_config
    base_platform.start
    puts "Installing packages in container #{base_platform.name}"
    case base_platform.name
    when "b-ubuntu-1004"
      base_platform.run_command("apt-get update")
      base_platform.run_command("apt-get install -y standard^ server^ vim-nox emacs23-nox curl tree")
    when "b-ubuntu-1204"
      base_platform.run_command("apt-get update")
      base_platform.run_command("apt-get install -y standard^ server^ vim-nox emacs23-nox tree")
    when "b-centos-5", "b-centos-6"
      base_platform.run_command("yum install -y @base @core vim-enhanced emacs-nox tree")
    end
    base_platform.stop
    return base_platform
  end

  def self.assign_ip_address(ipaddress, container_name, hwaddr)
    puts "Assigning IP address #{ipaddress} to #{container_name} container's lxc.network.hwaddr #{hwaddr}"
    search_file_delete_line("/etc/lxc/dhcp-hosts.conf", /(^#{hwaddr}|,#{ipaddress}$)/)
    append_line_to_file("/etc/lxc/dhcp-hosts.conf", "#{hwaddr},#{ipaddress}\n")
    reload_dnsmasq
  end

  def self.create_dns_record(api_fqdn, container_name, ipaddress)
    dns_record = "#{ipaddress} #{container_name} #{api_fqdn}\n"
    puts "Creating DNS record: #{dns_record}"
    search_file_delete_line("/etc/lxc/addn-hosts.conf", /^#{ipaddress}\s/)
    append_line_to_file("/etc/lxc/addn-hosts.conf", dns_record)
    reload_dnsmasq
  end

  def self.reload_dnsmasq
    system("pkill -HUP dnsmasq")
  end

  def self.search_file_delete_line(file_name, regex)
    IO.write(file_name, IO.readlines(file_name).delete_if {|line| line.match(Regexp.new(regex))}.join)
  end

  def self.append_line_to_file(file_name, line)
    content = IO.readlines(file_name)
    content[-1] = content[-1].chomp + "\n"
    content << line
    IO.write(file_name, content.join)
  end

  def self.search_file_replace(file_name, regex, replace)
    IO.write(file_name, IO.readlines(file_name).map {|line| line.gsub(Regexp.new(regex), replace)}.join)
  end
end
