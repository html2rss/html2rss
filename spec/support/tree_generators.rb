# frozen_string_literal: true

require 'prop_check'

##
# PropCheck generators and a mutator for nested hash trees, for +:property+ examples.
module TreeGenerators
  module_function

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
