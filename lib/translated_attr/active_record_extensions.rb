module TranslatedAttr

  module Validators
    # Presence Validators
    class TranslationsPresenceValidator < ActiveModel::EachValidator
      def validate_each(record, attribute, value)
        translations_present = record.translations.map{ |t| t.locale.try(:to_sym) }
        I18n.available_locales.each do |locale|
          unless translations_present.include?(locale)
            record.errors[attribute] <<
                I18n.t('translated_attr.errors.translations_presence',
                       :attr => I18n.t("activerecord.attributes.#{record.class.name.downcase}.name"),
                       :lang => locale)
          end
        end
      end
    end

    # Uniqueness validator
    class TranslationsUniqValidator < ActiveModel::EachValidator
      def validate_each(record, attribute, value)
        translations_present = record.translations.map{ |t| t.locale.try(:to_sym) }
        # Removes duplicate elements from self.
        # Returns nil if no changes are made (that is, no duplicates are found).
        if translations_present.uniq!
          record.errors[attribute] << I18n.t('translated_attr.errors.translations_uniq')
        end
      end
    end
  end

  module ActiveRecordExtensions
    module ClassMethods
      # Configure translation model dependency.
      # Eg:
      #   class PostTranslation < ActiveRecord::Base
      #     translations_for :post
      #   end
      def translations_for(model)
        belongs_to model

        validates :locale,
                  :presence => true,
                  :uniqueness => { :scope => "#{model}_id" },
                  :inclusion => I18n.available_locales.map{ |l| l.to_s }

        # dynamic class methods
        (class << self; self; end).class_eval do
          define_method "attribute_names_for_translation" do
            attribute_names - ["id", "#{model}_id", "locale", "created_at", "updated_at"]
          end
        end
      end

      # Configure translated attributes.
      # Eg:
      #   class Post < ActiveRecord::Base
      #     translated_attr :title, :description
      #   end
      def translated_attr(*attributes)
        make_it_translated! unless included_modules.include?(InstanceMethods)

        attributes.each do |attribute|
          # dynamic validations
          # TODO forse va sul metodo translations_for...
          validates attribute, :translation_presence => true, :translation_uniq => true

          #dynamic finders
          (class << self; self; end).class_eval do
            define_method "find_by_#{attribute}" do |value|
              self.send("find_all_by_#{attribute}".to_sym, value).first
            end

            define_method "find_all_by_#{attribute}" do |value|
              joins(:translations).
                  where("#{self.to_s.tableize.singularize}_translations.locale" => "#{I18n.locale}",
                        "#{self.to_s.tableize.singularize}_translations.#{attribute}" => "#{value}").
                  readonly(false)
            end

            define_method "find_or_new_by_#{attribute}" do |value|
              self.send("find_by_#{attribute}".to_sym, value) || self.new { |r| r.send("#{attribute}=", value) }
            end
          end

          # this make possible to specify getter and setter methods per locale,
          # eg: given title attribute you can use getter
          # as: title_en or title_it and setter as title_en= and title_it=
          I18n.available_locales.each do |locale|

            define_method "#{attribute}_#{locale}=" do |value|
              set_attribute(attribute, value, locale)
            end

            define_method "#{attribute}_#{locale}" do
              return localized_attributes[locale][attribute] if localized_attributes[locale][attribute]
              return if new_record?
              translations.where(:locale => "#{locale}").first.send(attribute.to_sym) rescue nil
            end

            # extension to the above dynamic finders
            (class << self; self; end).class_eval do
              define_method "find_by_#{attribute}_#{locale}" do |value|
                self.send("find_all_by_#{attribute}_#{locale}".to_sym, value).first
              end

              define_method "find_all_by_#{attribute}_#{locale}" do |value|
                joins(:translations).
                    where("#{self.to_s.tableize.singularize}_translations.locale" => "#{locale}",
                          "#{self.to_s.tableize.singularize}_translations.#{attribute}" => "#{value}").
                    readonly(false)
              end

              define_method "find_or_new_by_#{attribute}_#{locale}" do |value|
                self.send("find_by_#{attribute}_#{locale}".to_sym, value) ||
                    self.new { |r| r.send("#{attribute}_#{locale}=", value) }
              end
            end
          end

          # attribute setter
          define_method "#{attribute}=" do |value|
            set_attribute(attribute, value)
          end

          # attribute getter
          define_method attribute do
            # return previously setted attributes if present
            return localized_attributes[I18n.locale][attribute] if localized_attributes[I18n.locale][attribute]
            return if new_record?

            # Lookup chain:
            # if translation not present in current locale,
            # use default locale, if present.
            # Otherwise use first translation
            translation = translations.detect { |t| t.locale.to_sym == I18n.locale && t[attribute] } ||
                translations.detect { |t| t.locale.to_sym == translations_default_locale && t[attribute] } ||
                translations.first

            translation ? translation[attribute] : nil
          end

          define_method "#{attribute}_before_type_cast" do
            self.send(attribute)
          end

          define_method "modified?" do
            if valid?   # force the update_translations! method
              translations.map_by_changed?.any? || changed?
            end
          end
        end
      end

      private

      # Configure model
      def make_it_translated!
        include InstanceMethods

        has_many :translations,
                 :class_name => "#{self.to_s}Translation",
                 :dependent => :destroy,
                 :order => "created_at DESC"

        before_validation :update_translations!

        validates_associated :translations

        accepts_nested_attributes_for :translations
      end
    end

    module InstanceMethods

      def set_attribute(attribute, value, locale = I18n.locale)
        localized_attributes[locale][attribute] = value
      end

      def find_or_create_translation(locale)
        locale = locale.to_s
        (find_translation(locale) || self.translations.new).tap do |t|
          t.locale = locale
        end
      end

      def all_translations
        t = I18n.available_locales.map do |locale|
          [locale, find_or_create_translation(locale)]
        end
        ActiveSupport::OrderedHash[t]
      end

      def find_translation(locale)
        locale = locale.to_s
        translations.detect { |t| t.locale == locale }
      end

      def translations_default_locale
        return default_locale.to_sym if respond_to?(:default_locale)
        return self.class.default_locale.to_sym if self.class.respond_to?(:default_locale)
        I18n.default_locale
      end

      # attributes are stored in @localized_attributes instance variable via setter
      def localized_attributes
        @localized_attributes ||= Hash.new { |hash, key| hash[key] = {} }
      end

      # called before validations
      def update_translations!
        return if @localized_attributes.blank?
        @localized_attributes.each do |locale, attributes|
          translation = find_translation(locale)
          if translation
            attributes.each { |attribute, value| translation.send("#{attribute}=", value) }
          else
            translations.build(attributes.merge(:locale => locale.to_s))
          end
        end
      end

    end
  end
end

ActiveRecord::Base.extend TranslatedAttr::ActiveRecordExtensions::ClassMethods

# Compatibility with ActiveModel validates method which matches option keys to their validator class
# Used here in 'translated_attr' method
ActiveModel::Validations::TranslationPresenceValidator = TranslatedAttr::Validators::TranslationsPresenceValidator
ActiveModel::Validations::TranslationUniqValidator = TranslatedAttr::Validators::TranslationsUniqValidator
