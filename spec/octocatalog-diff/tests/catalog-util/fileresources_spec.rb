require 'fileutils'
require 'json'

require_relative '../spec_helper'

require OctocatalogDiff::Spec.require_path('/catalog')
require OctocatalogDiff::Spec.require_path('/catalog-util/fileresources')

describe OctocatalogDiff::CatalogUtil::FileResources do
  def catalog_from_fixture(path)
    OctocatalogDiff::Catalog.new(json: File.read(OctocatalogDiff::Spec.fixture_path(path)))
  end

  describe '#convert_file_resources' do
    before(:each) do
      @tmpdir = Dir.mktmpdir
      FileUtils.cp_r OctocatalogDiff::Spec.fixture_path('repos/tiny-repo/modules'), @tmpdir
      Dir.mkdir File.join(@tmpdir, 'environments')
      File.symlink @tmpdir, File.join(@tmpdir, 'environments', 'production')
    end

    after(:each) do
      FileUtils.remove_entry_secure @tmpdir if File.directory?(@tmpdir)
    end

    it 'should use compilation directory if environments/production is unavailable' do
      FileUtils.rm_f File.join(@tmpdir, 'environments', 'production')

      # Set up test
      obj = catalog_from_fixture('catalogs/catalog-test-file-v4.json')
      obj.compilation_dir = @tmpdir
      resources_save = obj.resources.dup

      # Perform test
      OctocatalogDiff::CatalogUtil::FileResources.convert_file_resources(obj)
      expect(obj.resources).to be_a_kind_of(Array), obj.resources.to_json
      expect(obj.resources.size).to eq(3), obj.resources.to_json
      expect(obj.resources[0]).to eq(resources_save[0]), obj.resources.to_json
      expect(obj.resources[1]).to eq(resources_save[1]), obj.resources.to_json
      expect(obj.resources[2]['parameters']['content']).to eq("foo\n"), obj.resources.to_json
      expect(obj.resources[2]['parameters'].key?('source')).to eq(false), obj.resources.to_json

      # Make sure the symlink isn't there, i.e. that we actually tested this
      expect(File.exist?(File.join(@tmpdir, 'environments', 'production'))).to eq(false)
    end

    it 'should not run at all if modules directory cannot be found' do
      module_dir = File.join(@tmpdir, 'modules')
      FileUtils.remove_entry_secure module_dir if File.directory?(module_dir)

      # Set up test
      obj = catalog_from_fixture('catalogs/catalog-test-file-v4.json')
      obj.compilation_dir = @tmpdir

      # Perform test
      OctocatalogDiff::CatalogUtil::FileResources.convert_file_resources(obj)
      expect(obj.resources).to be_a_kind_of(Array), obj.resources.to_json
      expect(obj.resources.size).to eq(3), obj.resources.to_json
      expect(obj.resources[2]['parameters']['source']).to eq('puppet:///modules/test/tmp/foo')
      expect(obj.resources[2]['parameters'].key?('content')).to eq(false), obj.resources.to_json
    end

    it 'should modify array with convertible resources' do
      # Set up test
      obj = catalog_from_fixture('catalogs/catalog-test-file-v4.json')
      obj.compilation_dir = @tmpdir
      resources_save = obj.resources.dup

      # Perform test
      OctocatalogDiff::CatalogUtil::FileResources.convert_file_resources(obj)
      expect(obj.resources).to be_a_kind_of(Array), obj.resources.to_json
      expect(obj.resources.size).to eq(3), obj.resources.to_json
      expect(obj.resources[0]).to eq(resources_save[0]), obj.resources.to_json
      expect(obj.resources[1]).to eq(resources_save[1]), obj.resources.to_json
      expect(obj.resources[2]['parameters']['content']).to eq("foo\n"), obj.resources.to_json
      expect(obj.resources[2]['parameters'].key?('source')).to eq(false), obj.resources.to_json
    end

    it 'should return unmodified array with no convertible resources' do
      # Set up test
      obj = catalog_from_fixture('catalogs/catalog-test-file-v4.json')
      obj.compilation_dir = @tmpdir
      obj.resources[2]['parameters']['content'] = 'buzz'
      resources_save = obj.resources.dup

      # Perform test
      OctocatalogDiff::CatalogUtil::FileResources.convert_file_resources(obj)
      expect(obj.resources).to eq(resources_save)
    end

    it 'should raise error if sourced file is not found' do
      # Set up test
      obj = catalog_from_fixture('catalogs/catalog-test-file-v4.json')
      obj.compilation_dir = @tmpdir
      obj.resources[2]['parameters']['source'] = 'puppet:///modules/this/does/not/exist'

      # Perform test
      expect do
        OctocatalogDiff::CatalogUtil::FileResources.convert_file_resources(obj)
      end.to raise_error(Errno::ENOENT, %r{Unable to resolve 'puppet:///modules/this/does/not/exist'})
    end

    it 'should return original if compilation_dir is not a string' do
      # Set up test
      obj = catalog_from_fixture('catalogs/catalog-test-file-v4.json')
      obj.compilation_dir = %w(foo bar)
      resources_save = obj.resources.dup

      # Perform test
      OctocatalogDiff::CatalogUtil::FileResources.convert_file_resources(obj)
      expect(obj.resources).to eq(resources_save)
    end

    it 'should return original if compilation_dir is empty string' do
      # Set up test
      obj = catalog_from_fixture('catalogs/catalog-test-file-v4.json')
      obj.compilation_dir = ''
      resources_save = obj.resources.dup

      # Perform test
      OctocatalogDiff::CatalogUtil::FileResources.convert_file_resources(obj)
      expect(obj.resources).to eq(resources_save)
    end

    it 'should return md5sum if there are non-ASCII characters in the file' do
      # Set up test
      obj = catalog_from_fixture('catalogs/catalog-test-file-v4.json')
      obj.compilation_dir = @tmpdir
      resources_save = obj.resources.dup
      File.open(File.join(@tmpdir, 'modules', 'test', 'files', 'tmp', 'foo'), 'w') { |f| f.write "\u0256" }

      # Perform test
      OctocatalogDiff::CatalogUtil::FileResources.convert_file_resources(obj)
      expect(obj.resources).to be_a_kind_of(Array)
      expect(obj.resources.size).to eq(3)
      expect(obj.resources[0]).to eq(resources_save[0])
      expect(obj.resources[1]).to eq(resources_save[1])
      expect(obj.resources[2]['parameters']['content']).to eq('{md5}165406e473f38ababa17a05696e2ef70')
      expect(obj.resources[2]['parameters'].key?('source')).to eq(false)
    end

    it 'should handle JSON generator error' do
      obj = catalog_from_fixture('catalogs/catalog-test-file-v4.json')
      obj.compilation_dir = @tmpdir
      allow(JSON).to receive(:generate).and_raise(::JSON::GeneratorError, 'test')
      OctocatalogDiff::CatalogUtil::FileResources.convert_file_resources(obj)
      expect(obj.error_message).to eq('Failed to generate JSON: test')
    end
  end

  describe '#resource_convertible?' do
    it 'should return true when a resource is convertible' do
      resource = {
        'type' => 'File',
        'parameters' => {
          'source' => 'puppet:///modules/foo/bar.txt'
        }
      }
      expect(OctocatalogDiff::CatalogUtil::FileResources.resource_convertible?(resource)).to eq(true)
    end

    it 'should return false when a resource is not a file' do
      resource = {
        'type' => 'Exec',
        'parameters' => {
          'command' => '/bin/false'
        }
      }
      expect(OctocatalogDiff::CatalogUtil::FileResources.resource_convertible?(resource)).to eq(false)
    end

    it 'should return false when a file resource is missing a source' do
      resource = {
        'type' => 'File',
        'parameters' => {
          'owner' => 'root'
        }
      }
      expect(OctocatalogDiff::CatalogUtil::FileResources.resource_convertible?(resource)).to eq(false)
    end

    it 'should return false when a file resource has content defined' do
      resource = {
        'type' => 'File',
        'parameters' => {
          'source' => 'puppet:///modules/foo/bar.txt',
          'content' => 'hello world'
        }
      }
      expect(OctocatalogDiff::CatalogUtil::FileResources.resource_convertible?(resource)).to eq(false)
    end

    it 'should return false when a file resource source does not match the pattern' do
      resource = {
        'type' => 'File',
        'parameters' => {
          'source' => 'what is going on here?'
        }
      }
      expect(OctocatalogDiff::CatalogUtil::FileResources.resource_convertible?(resource)).to eq(false)
    end
  end
end
