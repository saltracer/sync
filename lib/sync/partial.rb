module Sync
  class Partial
    attr_accessor :name, :resource, :context

    def self.all(model, context, scope = nil)
      resource = Resource.new(model, scope)

      plural_names = resource.plural_names

      partials = plural_names.collect do |plural_name|
        Dir["#{Sync.views_root}/#{plural_name}/_*.*"]
      end.flatten.compact

      partials.map do |partial|
        partial_name = File.basename(partial)
        Partial.new(partial_name[1...partial_name.index('.')], resource.model, scope, context)
      end
    end

    def initialize(name, resource, scope, context)
      self.name = name
      self.resource = Resource.new(resource, scope)
      self.context = context
    end

    def render_to_string
      context.render_to_string(partial: path, locals: locals, formats: [:html])
    end

    def render
      context.render(partial: path, locals: locals, formats: [:html])
    end

    def sync(action)
      message(action).publish
    end

    def message(action)
      Sync.client.build_message channel_for_action(action),
        html: (render_to_string unless action.to_s == "destroy")
    end

    def authorized?(auth_token)
      self.auth_token == auth_token
    end

    def auth_token
      @auth_token ||= Channel.new("#{polymorphic_path}-_#{name}").to_s
    end
    
    # For the refetch feature we need an auth_token that wasn't created
    # with scopes, because the scope information is not available on the
    # refetch-request. So we create a refetch_auth_token which is based 
    # only on model_name and id plus the name of this partial
    #
    def refetch_auth_token
      @refetch_auth_token ||= Channel.new("#{model_path}-_#{name}").to_s
    end

    def channel_prefix
      @channel_prefix ||= auth_token
    end
    
    def update_channel_prefix
      @update_channel_prefix ||= refetch_auth_token
    end

    def channel_for_action(action)
      case action
      when :update
        "#{update_channel_prefix}-#{action}"
      else
        "#{channel_prefix}-#{action}"
      end
    end

    def selector_start
      "#{channel_prefix}-start"
    end

    def selector_end
      "#{channel_prefix}-end"
    end

    def creator_for_scope(scope)
      PartialCreator.new(name, resource.model, scope, context)
    end


    private

    def path
      "sync/#{plural_name}/#{name}"
    end

    def locals
      locals_hash = {}
      locals_hash[plural_name.singularize.to_sym] = resource.model
      locals_hash
    end

    def model_path
      resource.model_path
    end

    def polymorphic_path
      resource.polymorphic_path
    end

    def plural_name

      partials = resource.plural_names.collect do |plural_name|
        Dir["#{Sync.views_root}/#{plural_name}"]
      end.flatten.compact

      partials[0].split("/")[-1]
    end

  end
end
