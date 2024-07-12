#!/bin/bash
echo export env variables
export TF_VAR_gcp_dns_zone=           # DNS zone(subdomain) you are using to access the btp platform, eg btp.settlemint.com
export TF_VAR_gcp_project_id=         # gcp project id where you setup BTP platform
export TF_VAR_gcp_region=             # where cluster will deploy
export TF_VAR_gcp_client_id=          # from OAuth2 Provider Setup step
export TF_VAR_gcp_client_secret=      # from OAuth2 Provider Setup step
export TF_VAR_oci_registry_username=  # provided by Customer Success Team
export TF_VAR_oci_registry_password=  # provided by Customer Success Team
export TF_VAR_btp_version=            # provided by Customer Success Team
env | grep TF_
