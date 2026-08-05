# AWS — Interview Q&A (based on this project)

**Q: Why does this project use a public subnet with `map_public_ip_on_launch = true` instead
of a private subnet behind a NAT gateway?**
A: NAT gateways cost money per hour and per GB processed, and add complexity (extra subnet,
extra route table, Elastic IP) that isn't needed for a single instance that's *meant* to be
publicly reachable (it's serving a web app). A public subnet with a security group
restricting inbound traffic to only the necessary ports is simpler and cheaper for this use
case. It also avoids NAT gateway costs, which matters on a time-boxed learning budget.

**Q: What's the difference between a Security Group and a Network ACL, and which does this
project use?**
A: A Security Group is **stateful** and attached to instances/ENIs — if you allow inbound
traffic on a port, the matching outbound response is automatically allowed. A Network ACL is
**stateless** and attached to subnets — you must explicitly allow both directions. This
project only defines a Security Group (`thermos-sg`), relying on the VPC's default (allow
all) NACL, which is standard for a simple setup like this.

**Q: Why is opening port 22 (SSH) to `0.0.0.0/0` flagged as a "WARNING" in the Terraform
comments?**
A: Because it means *anyone on the internet* can attempt to SSH into the instance (though
they'd still need valid credentials/key). In a real production environment, you'd restrict
the `cidr_blocks` for port 22 to a known IP range (office network, VPN, bastion host) instead
of the whole internet. It's left open here for workshop convenience, with an explicit
comment calling that out.

**Q: What is `t3.medium`, and why is it a common choice for workshops/free-tier learning?**
A: It's a burstable-performance EC2 instance type with 2 vCPUs and 1 GB RAM, part of AWS's
Free Tier eligibility and one of the few instance types allowed on constrained sandbox
environments like KodeKloud's AWS Playground. "Burstable" means it accumulates CPU credits
during idle periods and can burst above its baseline briefly, at the cost of throttling if
credits run out (see: CPU credit mode).

**Q: What does "CPU credit mode: Standard vs Unlimited" mean for a `t3` instance, and why
does it matter on a shared playground?**
A: Standard mode throttles the instance back to its baseline performance once its CPU credit
balance is exhausted. Unlimited mode allows it to burst indefinitely, incurring extra charges
— which is exactly why constrained sandbox platforms like KodeKloud disallow Unlimited mode
and reset any instance found using it, sometimes suspending the whole session as a
consequence.

**Q: Why does the EC2 instance need `user_data` at all — couldn't you just SSH in and set it
up manually?**
A: `user_data` makes the deployment reproducible and hands-off: every time Terraform creates
a fresh instance, it boots into a known, working state automatically (Docker installed, app
cloned, containers running) without a human repeating manual steps. This is the core idea
behind Infrastructure as Code — the *process* of setting up a server is captured in version
control, not just the server's final state.

**Q: What would you change about this architecture before letting real users hit it in
production?**
A: At minimum: move the database off the EC2 instance and onto managed RDS (with automated
backups/multi-AZ), put an Application Load Balancer + Auto Scaling Group in front of
multiple instances across at least two AZs, restrict the security group's SSH access, add
HTTPS via ACM + the load balancer, and move Terraform state to a remote backend with
locking. That's the direction the companion `ecommerce-devops-project` (EKS-based) takes.
