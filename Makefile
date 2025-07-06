.PHONY: build deploy-mupay deploy-multisig deploy-all clean chmod-deploy

chmod-deploy:
	chmod +x ./tools/deploy.sh

build:
	@echo "Building contracts..."
	forge build
	forge test

deploy-mupay: chmod-deploy
	@echo "Deploying MuPay contract..."
	./tools/deploy.sh mupay 314159

deploy-multisig: chmod-deploy
	@echo "Deploying Multisig contract..."
	./tools/deploy.sh multisig 314159

deploy-all: deploy-mupay deploy-multisig

clean:
	forge clean