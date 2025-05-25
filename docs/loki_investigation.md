# Loki Investigation and Proper Grafana Configuration

## 🔍 **Current Loki Status**

### ✅ **Loki is Working Correctly**
- **Pods**: `loki-0` (1/1 Running), `loki-promtail-85hwk` (1/1 Running)
- **Service**: `loki.loki.svc.cluster.local:3100` (ClusterIP: 10.43.221.204)
- **External Access**: `http://loki.dev.tese.io` - Working
- **API Endpoints**: All responding correctly
- **Log Collection**: Promtail is actively collecting logs

### 📊 **Verified Loki Functionality**
```bash
# Health check
curl -s http://loki.dev.tese.io/ready
# Response: ready

# Available labels
curl -s http://loki.dev.tese.io/loki/api/v1/labels
# Response: {"status":"success","data":["app","component","container","filename","instance","job","namespace","node_name","pod","stream"]}

# Working LogQL query
curl -s -G "http://loki.dev.tese.io/loki/api/v1/query" --data-urlencode 'query={job=~".+"}' --data-urlencode 'limit=5'
# Response: Returns actual log entries from pgAdmin and other pods
```

### 🏷️ **Available Job Labels**
Loki is collecting logs with job format: `namespace/pod-name`
Examples:
- `loki/loki` - Loki pod logs
- `monitoring/grafana` - Grafana pod logs  
- `pgadmin/pgadmin` - PgAdmin pod logs
- `cattle-system/rancher` - Rancher pod logs

## ❌ **Current Grafana Configuration Issues**

### **Problem 1: Wrong URL**
- **Current**: `http://loki.dev.tese.io/loki/api`
- **Issue**: Using external URL instead of internal cluster service
- **Issue**: Incorrect path suffix `/loki/api`

### **Problem 2: Network Access**
- Grafana should use internal cluster networking
- External URL adds unnecessary network hops and potential failures

### **Problem 3: Missing Configuration**
- No proper timeout settings
- No max lines configuration
- Missing derived fields for better log analysis

## ✅ **Correct Loki Data Source Configuration**

### **Proper URL**: 
```
http://loki.loki.svc.cluster.local:3100
```

### **Key Configuration Points**:
1. **URL**: Use internal cluster service name
2. **Port**: 3100 (Loki's HTTP port)
3. **Path**: No additional path needed
4. **Access**: Proxy mode (Grafana proxies requests)
5. **Auth**: None required (auth_enabled: false in Loki config)

## 🔧 **LogQL Query Requirements**

### **Important**: Loki requires non-empty matchers
- ❌ `{job=~".*"}` - Not allowed (empty-compatible)
- ✅ `{job=~".+"}` - Correct (non-empty matcher)
- ✅ `{namespace="monitoring"}` - Specific value matcher

### **Sample Working Queries**:
```logql
# All logs (any job)
{job=~".+"}

# Specific namespace
{namespace="monitoring"}

# Specific pod
{job="loki/loki"}

# Error logs
{job=~".+"} |= "error"

# Logs from last 5 minutes
{job=~".+"} [5m]
```

## 🎯 **Next Steps**

1. **Update Loki Data Source URL** to use internal cluster service
2. **Test connection** from Grafana
3. **Verify LogQL queries** work in Grafana Explore
4. **Create sample dashboard** with log panels

## 📝 **Loki Configuration Summary**
- **Auth**: Disabled (`auth_enabled: false`)
- **Storage**: Filesystem-based
- **Retention**: No retention configured (retention_period: 0s)
- **Schema**: v11 with boltdb-shipper
- **Ports**: HTTP 3100, gRPC 9095

The issue is **not with Loki itself** but with **how Grafana is configured to connect to it**. 