module Api
  module V0
    class ListingsController < ApiController
      include Pundit
      include ListingsToolkit

      before_action :authenticate_with_api_key_or_current_user!, only: %i[create update]
      before_action :authenticate_with_api_key_or_current_user, only: %i[show]

      before_action :set_listing, only: %i[update]

      before_action :set_cache_control_headers, only: %i[index show]

      skip_before_action :verify_authenticity_token, only: %i[create update]

      def index
        @listings = Listing.published.
          select(ATTRIBUTES_FOR_SERIALIZATION).
          includes(:user, :organization, :taggings, :listing_category)

        if params[:category].present?
          @listings = @listings.in_category(params[:category])
        end
        @listings = @listings.order(bumped_at: :desc)

        per_page = (params[:per_page] || 30).to_i
        num = [per_page, 100].min
        page = params[:page] || 1
        @listings = @listings.page(page).per(num)

        set_surrogate_key_header Listing.table_key, @listings.map(&:record_key)
      end

      def show
        relation = Listing.published

        # if the user is authenticated we allow them to access
        # their own unpublished listings as well
        relation = relation.union(@user.listings) if @user

        @listing = relation.select(ATTRIBUTES_FOR_SERIALIZATION).find(params[:id])

        set_surrogate_key_header @listing.record_key
      end

      def create
        super
      end

      def update
        super
      end

      # Note: since this is used for selecting from the DB, we need to use the
      # actual column name for the listing category, prefixed with classified_.
      ATTRIBUTES_FOR_SERIALIZATION = %i[
        id user_id organization_id title slug body_markdown cached_tag_list
        classified_listing_category_id processed_html published
      ].freeze
      private_constant :ATTRIBUTES_FOR_SERIALIZATION

      private

      attr_accessor :user

      alias current_user user

      def process_no_credit_left
        msg = "Not enough available credits"
        render json: { error: msg, status: 402 }, status: :payment_required
      end

      def process_successful_draft
        render "show", status: :created
      end

      def process_unsuccessful_draft
        render json: { errors: @listing.errors }, status: :unprocessable_entity
      end

      def process_successful_creation
        render "show", status: :created
      end

      def process_unsuccessful_creation
        render json: { errors: @listing.errors }, status: :unprocessable_entity
      end

      alias process_unsuccessful_update process_unsuccessful_creation

      def process_after_update
        render "show", status: :ok
      end

      def process_after_unpublish
        render "show", status: :ok
      end

      # Note: when doing the big listings refactoring we decided not to break
      # this API. Since other code assumes the params will be under listing,
      # we're copying them over.
      def listing_params
        params["listing"] = params["classified_listing"]
        super
      end
    end
  end
end