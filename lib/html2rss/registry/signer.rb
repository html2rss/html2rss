# frozen_string_literal: true

require 'openssl'

module Html2rss
  module Registry
    ##
    # Signs registry.v1 manifests using Ed25519 private keys.
    module Signer
      module_function

      ##
      # Writes a Base64-encoded Ed25519 signature for +manifest+.
      #
      # @param manifest [Manifest]
      # @param key_pem [String] PEM-encoded Ed25519 private key
      # @param bundle_dir [String, nil] bundle root; writes +manifest.sig+ when set
      # @param signature_path [String, nil] explicit signature destination
      # @return [String] path to the written signature file
      def sign!(manifest, key_pem:, bundle_dir: nil, signature_path: nil)
        target = signature_path || File.join(bundle_dir, Manifest::SIGNATURE_FILE)
        raise ArgumentError, 'bundle_dir or signature_path is required' if target.nil?

        private_key = OpenSSL::PKey.read(key_pem)
        ensure_ed25519!(private_key)

        signature = private_key.sign(nil, manifest.canonical_bytes)
        File.write(target, [signature].pack('m0'))
        target
      end

      ##
      # @param key [OpenSSL::PKey::PKey]
      # @return [void]
      def ensure_ed25519!(key)
        return if Verifier.ed25519_key?(key)

        raise ArgumentError, 'Signing key must be Ed25519'
      end

      private_class_method :ensure_ed25519!
    end
  end
end
