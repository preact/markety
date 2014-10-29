module Markety
  def self.new_client(access_key, secret_key, end_point, api_version = '2_2', log = false)
    client = Savon.client do
      endpoint end_point
      wsdl "http://app.marketo.com/soap/mktows/#{api_version}?WSDL"
      env_namespace "SOAP-ENV"
      namespaces({"xmlns:ns1" => "http://www.marketo.com/mktows/"})
      pretty_print_xml true
      log log
    end
    
    Client.new(client, Markety::AuthenticationHeader.new(access_key, secret_key))
  end
  
  class Client
    def initialize(savon_client, authentication_header)
      @client = savon_client
      @header = authentication_header
    end

    public

    # multiple lead functionality
    def get_multiple_leads_by_idnum(idnums)
      if !idnums.kind_of?(Array)
        idnums = []
      end

      get_multiple_leads(MultiLeadsKey.new(LeadKeyType::IDNUM, idnums))
    end

    def get_multiple_leads_by_email(emails)
      if !emails.kind_of?(Array)
        emails = []
      end

      get_multiple_leads(MultiLeadsKey.new(LeadKeyType::EMAIL, emails))
    end

    # lead functionality
    def get_lead_by_idnum(idnum)
      get_lead(LeadKey.new(LeadKeyType::IDNUM, idnum))
    end

    def get_lead_by_email(email)
      get_lead(LeadKey.new(LeadKeyType::EMAIL, email))
    end

    def sync_lead(email, first, last, company, mobile)
      lead_record = LeadRecord.new(email)
      lead_record.set_attribute('FirstName', first)
      lead_record.set_attribute('LastName', last)
      lead_record.set_attribute('Email', email)
      lead_record.set_attribute('Company', company)
      lead_record.set_attribute('MobilePhone', mobile)
      sync_lead_record(lead_record)
    end

    def sync_lead_record(lead_record)
      attributes = []
      lead_record.each_attribute_pair do |name, value|
        attributes << {:attr_name => name, :attr_value => value, :attr_type => lead_record.get_attribute_type(name) }
      end

      response = send_request(:sync_lead, {
        :dedup_enabled => true,
        :return_lead => true,
        :lead_record => {
          :email => lead_record.email,
          :lead_attribute_list => {
            :attribute => attributes
          }
        }
      })

      return LeadRecord.from_hash(response[:success_sync_lead][:result][:lead_record])
    end

    def sync_multiple_lead_records(lead_records, attributes_to_sync = nil)
      lead_record_list = []

      for lead_record in lead_records
        attributes = []

        # sync them all
        if attributes_to_sync == nil
          lead_record.each_attribute_pair do |name, value|
            attributes << {:attr_name => name, :attr_value => value, :attr_type => lead_record.get_attribute_type(name) }
          end
        # sync this subset
        else
          # we need email for deduping
          if (!attributes_to_sync.include?('Email'))
            attributes_to_sync << 'Email'
          end

          for attribute in attributes_to_sync
            attributes << {:attr_name => attribute, :attr_value => lead_record.get_attribute(attribute), :attr_type => lead_record.get_attribute_type(attribute) }
          end
        end

        lead_record_list << {
          :email => lead_record.email,
          :lead_attribute_list => {
            :attribute => attributes
          }
        }
      end

      response = send_request(:sync_multiple_leads, {
        :dedup_enabled => true,
        :lead_record_list => {:lead_record => lead_record_list}
      })
      return response[:success_sync_multiple_leads][:result][:sync_status_list]
    end

    def sync_lead_record_on_id(lead_record)
      idnum = lead_record.idnum
      raise 'lead record id not set' if idnum.nil?

      attributes = []
      lead_record.each_attribute_pair do |name, value|
        attributes << {:attr_name => name, :attr_value => value}
      end

      attributes << {:attr_name => 'Id', :attr_type => 'string', :attr_value => idnum.to_s}

      response = send_request(:sync_lead, {
        :return_lead => true,
        :lead_record =>
        {
          :lead_attribute_list => { :attribute => attributes},
          :id => idnum
        }
      })
      return LeadRecord.from_hash(response[:success_sync_lead][:result][:lead_record])
    end

    def get_lead_activity_by_email(email)
      lead_key = LeadKey.new('EMAIL', email)
      return send_request(:get_lead_activity, 
          {
            "leadKey" => lead_key.to_hash,
            "batchSize" => 100,
            "activityFilter" => {
              "excludeTypes" => { "activityType" => ["ChangeDataValue", "ChangeScore"] }
            }
          })
    end

    # MObject functionality
    def list_m_objects()
      response = send_request(:list_m_objects, {
        :params_list_mobjects => []
      })
      return response[:success_list_m_objects][:result]
    end

    # list functionality
    def add_to_list(list_key, idnum)
      list_operation(list_key, ListOperationType::ADD_TO, idnum)
    end

    def remove_from_list(list_key, idnum)
      list_operation(list_key, ListOperationType::REMOVE_FROM, idnum)
    end

    def is_member_of_list?(list_key, idnum)
      list_operation(list_key, ListOperationType::IS_MEMBER_OF, idnum)
    end

    private

    def list_operation(list_key, list_operation_type, idnum)
      response = send_request(:list_operation, {
        :list_operation   => list_operation_type,
        :list_key         => {
          :key_type => 'MKTOLISTNAME',
          :key_value => list_key
        },
        :strict           => 'false',
        :list_member_list => {
          :lead_key => [
            {:key_type => 'IDNUM', :key_value => idnum}
          ]
        }
      })
      if list_operation_type == ListOperationType::IS_MEMBER_OF
        return response[:success_list_operation][:result][:status_list][:lead_status][:status]
      else
        return response[:success_list_operation][:result][:success]
      end
    end

    def get_lead(lead_key)
      response = send_request(:get_lead, {"leadKey" => lead_key.to_hash})
      return LeadRecord.from_hash(response[:success_get_lead][:result][:lead_record_list][:lead_record])
    end

    def get_multiple_leads(lead_key)
      message = {
        "leadSelector" => {
          "keyType" => lead_key.key_type,
          "keyValues" => {
            "stringItem" => lead_key.key_values
          }
        },
        :attributes! => {"leadSelector" => { "xsi:type" => "ns1:LeadKeySelector" }}
      }
      response = send_request(:get_multiple_leads, message)
      return LeadRecord.from_hash_list(response[:success_get_multiple_leads][:result][:lead_record_list][:lead_record])
    end

    def send_request(namespace, message)
      @header.set_time(DateTime.now)
      response = request(namespace, message, @header.to_hash)
      response.to_hash
    end

    def request(namespace, message, header)
      @client.call(namespace, :message => message, :soap_header => header)
    end
  end
end
