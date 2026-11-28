# frozen_string_literal: true

require 'ipaddr'
require 'prop_check'

##
# Reusable PropCheck generators and value builders for +:property+ examples.
module PropertyGenerators
  module_function

  # @return [PropCheck::Generator] any IPv4 address (mostly public)
  def random_ipv4
    octet = PropCheck::Generators.choose(0..255)
    PropCheck::Generators.tuple(octet, octet, octet, octet).map { |octets| IPAddr.new(octets.join('.')) }
  end

  # @param ranges [Array<IPAddr>] CIDR ranges
  # @return [PropCheck::Generator] an address inside one of +ranges+, weighted toward each range's first and last
  def address_in(ranges)
    PropCheck::Generators.choose(0...ranges.size).bind { |index| inside(ranges[index]) }
  end

  # Shrinks toward the first address of +range+ because the offset, not the address, is drawn.
  #
  # @param range [IPAddr] a CIDR range
  # @return [PropCheck::Generator] an address of +range+, often its first or last
  def inside(range)
    first, last = range.to_range.minmax.map(&:to_i)
    generators = PropCheck::Generators
    edge = generators.one_of(generators.constant(0), generators.constant(last - first))
    generators.one_of(generators.choose(0..(last - first)), edge).map do |offset|
      IPAddr.new(first + offset, range.family)
    end
  end

  # @param ranges [Array<IPAddr>] CIDR ranges
  # @return [PropCheck::Generator] an address inside +ranges+ or a random IPv4 address
  def mixed_address(ranges)
    PropCheck::Generators.one_of(address_in(ranges), random_ipv4)
  end

  # @param ranges [Array<IPAddr>] CIDR ranges
  # @return [PropCheck::Generator] up to four {mixed_address}es, possibly none
  def resolver_answer(ranges)
    PropCheck::Generators.array(mixed_address(ranges), min: 0, max: 4)
  end

  # @param ipv4 [IPAddr] an IPv4 address
  # @return [Array<IPAddr>] +ipv4+ followed by its IPv4-mapped, NAT64 and 6to4 IPv6 spellings
  def ipv6_forms(ipv4)
    number = ipv4.to_i
    [ipv4, ipv4.ipv4_mapped,
     IPAddr.new(IPAddr.new('64:ff9b::').to_i | number, Socket::AF_INET6),
     IPAddr.new((0x2002 << 112) | (number << 80), Socket::AF_INET6)]
  end

  # @return [PropCheck::Generator] string-keyed hashes nesting hashes and arrays of hashes, with frozen string leaves
  def string_keyed_tree
    gen = PropCheck::Generators
    key = gen.alphanumeric_string.where { |text| !text.empty? }
    leaf = gen.one_of(gen.alphanumeric_string.map(&:freeze), gen.integer, gen.constant(nil), gen.constant(true))
    node = gen.tree(leaf) do |child|
      gen.frequency(1 => gen.hash_of(key, child, max: 3), 2 => gen.array(child, max: 3))
    end
    gen.hash_of(key, node, max: 4)
  end

  # Changes every mutable part of +tree+ in place: appends to arrays and strings, adds a key to hashes.
  #
  # @param tree [Object] a value from {string_keyed_tree}
  # @return [Object] +tree+
  def mutate!(tree)
    case tree
    when Hash then tree.each_value { |value| mutate!(value) }.store('mutated', true)
    when Array then tree.each { |value| mutate!(value) }.push(:mutated)
    when String then tree << 'mutated'
    end
    tree
  end
end
