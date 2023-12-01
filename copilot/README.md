# warp-app in AWS

The warp-app can be deployed to AWS using the [AWS Copilot CLI](https://aws.github.io/copilot-cli/).

The copilot CLI can be installed as follows:

```bash
brew install aws/tap/copilot-cli
```

## Usage

The warp-app is deployed in AWS in the following environments:

- euc1: eu-central-1
- ue1: us-east-1
- uw1: us-west-1

To run warp connect to one of the environments first:

```bash
copilot svc exec -e uw1
```

Once inside the warp-app container, you can run warp as follows:

```bash
/warp get --analyze.v \
    --host=dev-storage.aws.tigris.dev \
    --bucket=test-bucket-2 \
    --access-key=$ACCESS_KEY \
    --secret-key=$SECRET_KEY \
    --tls --obj.size=1KB --duration=1m --concurrent=40
```

## Deployment

**These steps are only needed if a fresh deployment is required.**

Initialize the app with the Copilot CLI:

```bash
copilot app init warp-app
```

Create the environment:

```bash
copilot env init --name uw1 --app warp-app --region us-west-1 --default-config
```

Deploy the environment:

```bash
copilot env deploy --name uw1
```

Initialize the service:

```bash
copilot svc init --name warp-app
```

Deploy the service:

```bash
copilot svc deploy --name warp-app --env uw1
```
