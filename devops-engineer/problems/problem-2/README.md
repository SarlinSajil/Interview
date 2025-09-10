# DevOps CI/CD Pipeline & GitOps Solution

## 🎯 Project Overview

This project implements a complete GitOps CI/CD pipeline for a FastAPI application, demonstrating modern DevOps practices including infrastructure as code, automated testing, security scanning, blue-green deployments, and comprehensive monitoring.

### Key Features

- **Multi-stage CI/CD Pipeline** with GitHub Actions
- **GitOps Deployment** with ArgoCD 
- **Blue-Green Deployment Strategy**
- **Infrastructure as Code** with Kubernetes and Helm
- **Comprehensive Security Scanning**
- **Monitoring & Alerting** with Prometheus and Grafana
- **Automated Testing** and validation
- **Multi-environment Support** (dev, staging, production)

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           Developer                             │
└─────────────────────────┬───────────────────────────────────────┘
                          │ git push
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                      GitHub Repository                         │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐│
│  │ Application │ │ Kubernetes  │ │ Helm Charts │ │   ArgoCD    ││
│  │    Code     │ │ Manifests   │ │             │ │Applications ││
│  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘│
└─────────────────────────┬───────────────────────────────────────┘
                          │ webhook trigger
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                    GitHub Actions CI/CD                        │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐│
│  │   Build &   │ │  Security   │ │   Testing   │ │   Docker    ││
│  │    Test     │ │  Scanning   │ │             │ │   Build     ││
│  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘│
└─────────────────────────┬───────────────────────────────────────┘
                          │ update manifests
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                        ArgoCD                                  │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                │
│  │     Dev     │ │   Staging   │ │ Production  │                │
│  │Environment  │ │Environment  │ │Environment  │                │
│  └─────────────┘ └─────────────┘ └─────────────┘                │
└─────────────────────────┬───────────────────────────────────────┘
                          │ deploy
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Kubernetes Cluster                            │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                │
│  │   Blue      │ │    Green    │ │ Monitoring  │                │
│  │Deployment   │ │ Deployment  │ │   Stack     │                │
│  └─────────────┘ └─────────────┘ └─────────────┘                │
└─────────────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### Prerequisites

- Docker and Docker Compose
- Kubernetes cluster (local or cloud)
- kubectl configured
- Helm 3.x
- ArgoCD installed on cluster
- GitHub repository with Actions enabled

### 1. Clone and Setup

```bash
git clone <your-repo-url>
cd devops-engineer/problems/problem-2

# Make scripts executable
chmod +x scripts/*.sh
```

### 2. Start Local Infrastructure

```bash
# Start DevOps services (from project root)
cd ../../../docker-compose
./start-devops.sh

# Wait for services to be ready
docker-compose -f base.yml -f devops.yml ps
```

### 3. Deploy to Development

```bash
# Deploy using Helm
helm upgrade --install devops-demo-dev ./helm/charts/app \
  --namespace dev \
  --create-namespace \
  --set image.repository=ghcr.io/your-org/devops-demo-app \
  --set image.tag=develop \
  --set environment=dev

# Validate deployment
./scripts/validate-deployment.sh dev
```

### 4. Configure ArgoCD

```bash
# Apply ArgoCD project and applications
kubectl apply -f argocd/projects/
kubectl apply -f argocd/applications/
```

## 📁 Project Structure

```
problem-2/
├── .github/workflows/          # GitHub Actions CI/CD pipelines
│   └── ci-cd.yml              # Main CI/CD workflow
├── app/                       # Sample FastAPI application
│   ├── src/main.py           # Application code
│   ├── tests/                # Unit tests
│   ├── Dockerfile            # Container definition
│   └── requirements.txt      # Python dependencies
├── k8s/                      # Kubernetes manifests
│   ├── base/                 # Base Kustomize resources
│   └── overlays/             # Environment-specific patches
│       ├── dev/
│       ├── staging/
│       └── prod/
├── helm/charts/app/          # Helm chart
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
├── argocd/                   # ArgoCD configurations
│   ├── projects/             # ArgoCD projects
│   └── applications/         # ArgoCD applications
├── monitoring/               # Monitoring configurations
│   ├── prometheus/           # Prometheus config and rules
│   ├── grafana/              # Grafana dashboards
│   └── alertmanager/         # Alertmanager config
├── scripts/                  # Utility scripts
├── docs/                     # Documentation
└── README.md                 # This file
```

## 🔄 CI/CD Pipeline

### Pipeline Stages

1. **Security Scanning**
   - Repository vulnerability scanning with Trivy
   - Secret detection with GitLeaks
   - SAST analysis

2. **Testing & Quality**
   - Unit test execution with pytest
   - Code coverage reporting
   - Static analysis with Pylint and Bandit
   - Dependency vulnerability scanning

3. **Build & Push**
   - Multi-platform Docker build
   - Container vulnerability scanning
   - Push to GitHub Container Registry

4. **Deploy Development**
   - Automated deployment to dev environment
   - Smoke testing
   - Integration test execution

5. **Deploy Staging**
   - Blue-green deployment strategy
   - Comprehensive testing
   - Manual approval gate

6. **Deploy Production**
   - Blue-green deployment with traffic switching
   - Production readiness tests
   - Automated rollback on failure

### Environment Strategies

- **Development**: Automatic deployment on `develop` branch
- **Staging**: Automatic deployment on `main` branch with manual approval
- **Production**: Manual deployment with strict validation

## 🔵🟢 Blue-Green Deployment

### Strategy Overview

Blue-green deployment eliminates downtime by running two identical production environments:

- **Blue**: Current live environment serving traffic
- **Green**: New version deployment for testing
- **Switch**: Traffic routing change after validation

### Implementation

```bash
# Deploy green version
helm upgrade --install app-green ./helm/charts/app \
  --set blueGreen.enabled=true \
  --set blueGreen.color=green \
  --set image.tag=v2.0.0

# Test green deployment
./scripts/run-production-tests.sh green

# Switch traffic to green
kubectl patch service app-prod \
  -p '{"spec":{"selector":{"app.kubernetes.io/color":"green"}}}'

# Cleanup blue deployment
helm uninstall app-blue
```

## 📊 Monitoring & Observability

### Metrics Collection

- **Application Metrics**: Custom metrics via `/metrics` endpoint
- **Infrastructure Metrics**: Node, pod, and cluster metrics
- **Business Metrics**: Counter, response times, error rates

### Alerting Rules

- **Critical Alerts**: Application down, high error rate, pod crashes
- **Warning Alerts**: High resource usage, slow response times
- **Info Alerts**: Deployment events, scaling events

### Dashboards

- Application performance and health
- Infrastructure resource utilization
- Business metrics and KPIs
- SLA and SLO tracking

## 🔒 Security

### Container Security

- Base image vulnerability scanning
- Non-root user execution
- Read-only root filesystem
- Security context constraints

### Network Security

- Network policies for pod isolation
- TLS encryption for all communications
- Ingress with SSL termination
- Service mesh ready

### Secret Management

- Kubernetes secrets for sensitive data
- External secret management integration
- Automatic secret rotation
- Least privilege access

## 🧪 Testing Strategy

### Testing Pyramid

1. **Unit Tests**: Fast, focused tests for individual functions
2. **Integration Tests**: API endpoint and database interaction tests
3. **Contract Tests**: API contract validation
4. **End-to-End Tests**: Full user journey validation
5. **Performance Tests**: Load testing and benchmarking
6. **Security Tests**: Vulnerability and penetration testing

### Test Automation

```bash
# Run all tests locally
cd app
python -m pytest tests/ -v --cov=src

# Run integration tests against deployed app
./scripts/run-integration-tests.sh staging

# Run production readiness tests
./scripts/run-production-tests.sh blue
```

## 🛠️ Operational Procedures

### Deployment Process

1. **Development**
   ```bash
   git checkout develop
   git commit -m "feat: new feature"
   git push origin develop
   # Automatic deployment to dev environment
   ```

2. **Staging**
   ```bash
   git checkout main
   git merge develop
   git push origin main
   # Automatic deployment to staging
   # Manual approval for production
   ```

3. **Production**
   ```bash
   # Trigger production deployment
   # Blue-green deployment with validation
   # Automated rollback on failure
   ```

### Rollback Procedures

#### Automatic Rollback
- Triggered by failed health checks
- Triggered by failed production tests
- Automatic traffic switching

#### Manual Rollback
```bash
# Helm rollback
helm rollback devops-demo-prod

# ArgoCD rollback
argocd app rollback devops-demo-production

# Traffic switch (blue-green)
kubectl patch service devops-demo-prod \
  -p '{"spec":{"selector":{"app.kubernetes.io/color":"blue"}}}'
```

### Troubleshooting

#### Common Issues

1. **Pod CrashLoopBackOff**
   ```bash
   kubectl logs -l app.kubernetes.io/name=devops-demo-app -n production
   kubectl describe pod <pod-name> -n production
   ```

2. **High Resource Usage**
   ```bash
   kubectl top pods -n production
   kubectl get hpa -n production
   ```

3. **Database Connection Issues**
   ```bash
   kubectl exec -it <pod-name> -n production -- curl localhost:8000/ready
   ```

#### Monitoring Alerts

- Check Grafana dashboards for metrics
- Review Prometheus alerts
- Check application logs in ELK stack

## 🔧 Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ENVIRONMENT` | Deployment environment | `development` |
| `REDIS_HOST` | Redis hostname | `redis` |
| `REDIS_PORT` | Redis port | `6379` |
| `POSTGRES_HOST` | PostgreSQL hostname | `postgres` |
| `POSTGRES_PORT` | PostgreSQL port | `5432` |
| `LOG_LEVEL` | Logging level | `INFO` |

### Helm Values

Key configuration options in `values.yaml`:

```yaml
# Replica configuration
replicaCount: 3

# Image configuration
image:
  repository: ghcr.io/your-org/devops-demo-app
  tag: "latest"

# Environment-specific settings
environment: production

# Blue-green deployment
blueGreen:
  enabled: true
  color: blue

# Resource limits
resources:
  requests:
    memory: "256Mi"
    cpu: "200m"
  limits:
    memory: "1Gi"
    cpu: "500m"
```

## 📈 Performance Tuning

### Application Optimization

- Connection pooling for database
- Redis caching for frequently accessed data
- Async request handling
- Resource limit tuning

### Infrastructure Optimization

- HPA configuration for auto-scaling
- Node affinity and anti-affinity rules
- Resource requests and limits
- Persistent volume optimization

### Monitoring Optimization

- Metric retention policies
- Alert rule optimization
- Dashboard performance
- Log aggregation efficiency

## 🚨 Disaster Recovery

### Backup Strategy

- Database automated backups
- Configuration backup
- Container image retention
- Disaster recovery testing

### Recovery Procedures

1. **Application Failure**: Automatic pod restart and scaling
2. **Node Failure**: Kubernetes automatic rescheduling
3. **Cluster Failure**: Multi-region deployment
4. **Data Loss**: Point-in-time recovery from backups

## 📚 Additional Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Implement changes with tests
4. Submit a pull request
5. Ensure CI/CD pipeline passes

## 📞 Support

For issues and questions:
- Create GitHub Issues for bugs and feature requests
- Check the troubleshooting guide
- Review monitoring dashboards
- Contact the DevOps team

---

This implementation demonstrates enterprise-grade DevOps practices with modern GitOps workflows, comprehensive testing, and production-ready monitoring and alerting.