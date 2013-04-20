#
# Author:: Pawel Kozlowski (<pawel.kozlowski@u2i.com>)
# Copyright:: Copyright (c) 2013 Pawel Kozlowski
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/mixin/deep_merge'

class Chef
  class Knife
    class ScribeAdjust < Chef::Knife

      include Chef::Mixin::DeepMerge

      TEMPLATE_HASH = { "author_name" => "",
        "author_email" => "",
        "description" => "",
        "adjustments" => []
      }

      ENVIRONMENT_ADJUSTMENT_TEMPLATE = {
        "adjustment" => { "default_attributes" => { },
          "override_attributes" => { },
          "cookbook_versions" => { }
        }
      }

      ROLE_ADJUSTMENT_TEMPLATE = {
        "adjustment" => { "default_attributes" => { },
          "override_attributes" => { },
          "run_list" => [ ]
        }
      }

      NODE_ADJUSTMENT_TEMPLATE = {
        "adjustment" => { "attributes" => { },
          "run_list" => [ ]
        }
      }

      banner "knife scribe adjust FILE [FILE..]"

      deps do

      end

      option :generate,
      :short => "-g",
      :long  => "--generate",
      :description => "generate adjustment templates"

      option :type,
      :short => "-t TYPE",
      :long  => "--type TYPE",
      :description => "generate adjustment templates [environemnt|node|role]",
      :default => "environment"

      alias_method :action_merge, :merge
      alias_method :action_hash_only_merge, :hash_only_merge

      def run
        if @name_args[0].nil?
          show_usage
          ui.fatal("At least one adjustment file needs to be specified!")
          exit 1
        end
        @name_args.each do |filename|
          if config[:generate] == true
            generate_template(filename)
          else
            apply_adjustment(filename)
          end
        end
      end

      def generate_template(filename)
        unless ["environment", "role", "node"].include?(config[:type])
          ui.fatal("Incorrect adjustment type! Only 'node', 'environment' or 'role' allowed.")
          exit 1
        end
        TEMPLATE_HASH["adjustments"] = [self.class.class_eval(config[:type].upcase + "_ADJUSTMENT_TEMPLATE")]
        File.open(filename, "w") { |file| file.write(JSON.pretty_generate(TEMPLATE_HASH)) }
      end

      def apply_adjustment(filename)
        if !File.exists?(filename)
          ui.fatal("File " + filename + " does not exist!")
        else
          begin
            adjustment_file = File.open(filename, "r") { |file| JSON.load(file) }
            if adjustment_file_valid? adjustment_file
              adjustment_file["adjustments"].each do |adjustment|
                if adjustment_valid? adjustment
                  query = adjustment["search"].include?(":") ? adjustment["search"] : "name:" + adjustment["search"]
                  Chef::Search::Query.new.search(adjustment["type"], query ) do |result|
                    result.class.json_create(send(("action_" + adjustment["action"]).to_sym, result.to_hash, adjustment["adjustment"])).save
                  end
                end
              end
            end
          rescue JSON::ParserError
            ui.fatal("Malformed JSON in " + filename + "!")
          end
        end
      end

      def adjustment_file_valid? adjustment_file
        unless adjustment_file.kind_of?(Hash)
          ui.fatal("Adjustment file must contain a JSON hash!")
          return false
        end

        unless adjustment_file["adjustments"].kind_of?(Array)
          ui.fatal("Adjustment file must contain an array of adjustments!")
          return false
        end
        true
      end

      def adjustment_valid? adjustment
        unless adjustment.kind_of?(Hash)
          ui.fatal("Adjustment must be a JSON hash!")
          return false
        end

        ["action", "type", "search", "adjustment"].each do |required_key|
          unless adjustment.has_key?(required_key)
            ui.fatal("Adjustment hash must contain " + required_key + "!")
            return false
          end
        end

        unless respond_to?("action_" + adjustment["action"])
          ui.fatal("Incorrect action!")
          return false
        end
        true
      end

      def action_overwrite(base, overwrite_with)
        if base.kind_of?(Hash) && overwrite_with.kind_of?(Hash)
          base.merge(overwrite_with)
        elsif overwrite_with.nil?
          base
        else
          overwrite_with
        end
      end
    end

    def deep_delete(delete_from, delete_spec)
      deep_delete!(delete_from.dup, delete_spec.dup)
    end

    alias_method :action_delete, :deep_delete

    def deep_delete!(delete_from, delete_spec)
      if delete_from.kind_of?(Hash) || delete_from.kind_of?(Array)
        if delete_spec.kind_of?(Array)
          delete_spec.each { |item| deep_delete!(delete_from, item) }
        elsif delete_spec.kind_of?(Hash)
          delete_spec.each { |key,item| deep_delete!(delete_from[key], item) }
        else
          delete_from.kind_of?(Array) ? delete_from.delete_at(delete_spec) : delete_from.delete(delete_spec)
        end
      end
      delete_from
    end
  end
end
