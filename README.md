# MuchTodo Backend – Deployment Assessment

Terraform provisions the AWS infrastructure for the MuchTodo Go backend; Docker Compose runs the backend and MongoDB on the backend EC2 instance behind an Application Load Balancer.

Application repo: <https://github.com/Innocent9712/much-to-do/tree/feature/backend-only> (Go module in `Server/MuchToDo`).

## Repository layout

```
backend-deployment-assessment/
├── terraform/
│   ├── main.tf                  # all resources
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── user_data/
│       ├── backend_setup.sh     # installs Docker + Docker Compose
│       └── mongodb_setup.sh     # installs and starts MongoDB
├── Dockerfile                   # multi-stage, non-root, HEALTHCHECK
├── docker-compose.yml           # backend + mongo, volume, network, restart policies
├── .env.example                 # runtime config template (copied to .env on the server)
├── .dockerignore
├── evidence/                    # screenshots
└── README.md
```

## Architecture

```
Internet ──80/443──> ALB (public subnets, 2 AZs)
                       │ 8080
                       ▼
                 Backend EC2 (private subnet) ──27017──> MongoDB EC2 (private subnet)
                       ▲
Your IP ──22──> Bastion EC2 (public subnet, Elastic IP) ──22──┘
Private subnets reach the internet through one NAT gateway (in public subnet 1).
```

| Component | Detail |
|---|---|
| VPC | `startuptech-vpc`, `10.0.0.0/16`, DNS support + hostnames enabled |
| Subnets | 2 public (`10.0.1.0/24`, `10.0.2.0/24`), 2 private (`10.0.11.0/24`, `10.0.12.0/24`), different AZs |
| Security groups | ALB: 80/443 from anywhere. Bastion: 22 from your IP. Backend: 8080 from ALB SG, 22 from bastion SG. MongoDB: 27017 from backend SG |
| EC2 | Bastion (public, Elastic IP), backend (private), MongoDB (private); all `t3.micro`, Amazon Linux 2 |
| ALB | Public subnets, target group on 8080, health check `/health`, listener on 80 |

## Phase 1 – Provision infrastructure

Prerequisites: Terraform >= 1.5, AWS credentials configured, and an existing EC2 key pair in the target region.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: my_ip (e.g. $(curl -s https://checkip.amazonaws.com)/32) and key_name

terraform init
terraform validate
terraform plan
terraform apply
```

Outputs: `vpc_id`, `alb_dns_name`, `bastion_public_ip`, `backend_private_ip`, `mongodb_private_ip`.

The user data scripts need a couple of minutes after the instances start. Check progress on an instance with `sudo tail -f /var/log/user-data.log`.

## Phase 2 – Docker

### Image

- Build stage: `golang:1.25-alpine` (matches `go 1.25.1` in `go.mod`). It clones the application repo (`APP_REPO`, `APP_REF` build args), generates the swagger `docs` package if the repo does not include it, and builds a static binary.
- Runtime stage: `alpine:3.20` with only the binary and CA certificates, running as a non-root `app` user.
- `EXPOSE 8080` and a `HEALTHCHECK` against `/health`.

### Compose

- `mongodb` (mongo:7.0): named volume `mongo_data`, healthcheck, `restart: unless-stopped`.
- `backend`: built from the Dockerfile, port 8080, `depends_on` MongoDB with `condition: service_healthy`, `restart: unless-stopped`.
- Both share the `muchtodo-net` network; the backend reaches Mongo at `mongodb://mongodb:27017`.
- The app loads config with viper from `./.env` in its working directory, so `.env` is mounted read-only at `/app/.env`.

Run locally:

```bash
cp .env.example .env     # set JWT_SECRET_KEY
chmod 644 .env           # must be readable by the non-root container user
docker compose up -d --build
curl http://localhost:8080/health
```

## Deployment to EC2

1. SSH to the backend server through the bastion (the key stays on your machine):

   ```bash
   ssh -i ~/.ssh/<key>.pem -J ec2-user@<bastion_public_ip> ec2-user@<backend_private_ip>
   ```

2. On the backend server (log out and back in once if `docker` needs sudo, because the group change applies on next login):

   ```bash
   git clone <this-repo-url> backend-deployment-assessment
   cd backend-deployment-assessment
   cp .env.example .env && nano .env     # set JWT_SECRET_KEY
   chmod 644 .env
   docker compose up -d --build
   docker compose ps
   ```

3. Verify through the load balancer:

   ```bash
   curl http://<alb_dns_name>/health
   ```

   The ALB target shows healthy once `/health` returns 200 (a couple of health-check intervals).

## Evidence

Screenshots go in `evidence/`: `terraform apply` output, the AWS console (VPC, instances, ALB target health), `docker compose ps` on the backend server, and `curl` against the ALB DNS name.

## Notes and decisions

- The Mongo instance from Phase 1 is provisioned and reachable from the backend (port 27017), but Phase 2 runs MongoDB as a Compose container, as the brief asks. Pointing `MONGO_URI` at `mongodb://<mongodb_private_ip>:27017` would use the standalone instance instead.
- MongoDB runs without authentication; access is limited to the backend security group. For production, enable auth and put credentials in `MONGO_URI`.
- A single NAT gateway keeps cost down but is a single point of failure for private-subnet outbound traffic.
- The ALB listens on HTTP only; port 443 is open on the security group but there is no listener, since no certificate was in scope.
- Redis caching is disabled (`ENABLE_CACHE=false`).

## Cleanup

```bash
cd terraform && terraform destroy
```
