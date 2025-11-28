# oec-erpportal-addon-cpar
Repo for oec erpportal addon compliance AR APIs

##Technologies
1. Token Service
2. OpenFeign
3. Kafka
4. RetryService
5. Scheduler service

#Import Charge#
API Async version
```mermaid
sequenceDiagram
    participant Browser
    participant Backend
    participant Queue
    participant CWIS_and_CW
    
    Browser->>Backend: import
    Backend->>Queue: (IMI) prepare to send
    Queue-->>Backend: prepare done
    Backend-->>Browser: 200 success
    Queue->>CWIS_and_CW: aSync Call inbound API
    Browser->>Backend: get detail
    Backend-->>Browser: IMI
    CWIS_and_CW-->>Backend: (IMC or IMW) return response
    Browser->>Backend: (refresh) get detail
    Backend-->>Browser: IMC, IMW
```
API Sync version
```mermaid
sequenceDiagram
    participant Browser
    participant Backend
    participant CWIS_and_CW
    
    Browser->>Backend: import
    Backend->>CWIS_and_CW: (IMI) Sync Call inbound API
    Browser->>Backend: (when API timeout) get detail until IMC or IMW with limited try
    Backend-->>Browser: IMI
    CWIS_and_CW-->>Backend: (IMC or IMW) return response
    Backend-->>Browser: 200 success
    Browser->>Backend: get detail
    Backend-->>Browser: IMC, IMW
```