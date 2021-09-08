# Database

## Tables
### alert
Current, processed alerts  

### new\_alert
New events that haven't been processed and added the the [alert] table.                  

### server
network devices and details.                     

### monitoring\_default_values  
The default values for various events.

### monitoring_values          
Per cluster/type/server overrided values for events.

### server_type                
Links servers and types.

### type
Defined server types:
#### Fields
 - auto\_id\_type: 'file' or 'snmp'
 - auto\_id_source: The filename or snmp id of the identifying object.
 - auto\_id_text: the matching text value that needs to exist to identify the particular type.

### type_module                
Agent modules defined for a particular type of server.

### action                     
### alert_journal              
### alert_summary              
### bu                         
### cage                       
### changelog                  
### changelog_detail           
### check_data                 
### cluster                    
### cluster_netblock           
### contacts                   
### cron_eta                   
### cron_log                   
### deleted_server             
### diskinfo                   
### escalations                
### filter                     
### hardware_detail            
### historical_Acknowledged    
### historical_ParentIdentifier
### historical_Severity        
### historical_Summary         
### historical_SuppressEscl    
### historical_Ticket          
### historical_alert           
### interface                  
### interface_alias            
### module                     
### netblock                   
### network                    
### object                     
### object_data                
### object_field               
### object_reference           
### object_tag                 
### object_text                
### object_type                
### process                    
### processed_alert            
### rack                       
### recurring_alert            
### rootcause                  
### rootcause_symptom          
### settings                   
### silo                       
### test_object                
### type_log                   
### type\_log_detail            
### type_process               
### user                       
### user_external              

