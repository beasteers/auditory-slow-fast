.ONESHELL:

EK_REPO_NAME := epic-kitchens-100-annotations
ES_REPO_NAME := epic-sounds-annotations
EK_DL_NAME := epic-kitchens-download-scripts
EK_NAME := epic-kitchens-100
OUTPUT_DIR := output
DATA_DIR := data
LOGS_DIR := logs
VENV_DIR := $${SCRATCH}/venv
REPO_DIR := $${SCRATCH}/marl-thesis
JOB_NAME := slowfast-training
MAIL_ADDRESS := $${USER}@nyu.edu

EXAMPLE_FILE := $(DATA_DIR)/EPIC-KITCHENS/P10/videos/P10_04_trimmed.wav

# Model weights
ASF_WEIGHTS_FILE := SLOWFAST_EPIC.pyth

# Conda activate
CONDA_ACTIVATE=source $$(conda info --base)/etc/profile.d/conda.sh ; conda activate ; conda activate


.PHONY: data
data: # This target clones the repos only if they don't exist in the data directory
	@mkdir -p $(DATA_DIR) # Create the data directory if it doesn't exist

	@if [ ! -d "$(DATA_DIR)/$(EK_REPO_NAME)" ]; then \
		cd $(DATA_DIR) && git submodule add https://github.com/epic-kitchens/$(EK_REPO_NAME) ; \
	fi

	@if [ ! -d "$(DATA_DIR)/$(ES_REPO_NAME)" ]; then \
		cd $(DATA_DIR) && git submodule add https://github.com/epic-kitchens/$(ES_REPO_NAME) ; \
	fi

	@if [ ! -d "$(DATA_DIR)/$(EK_DL_NAME)" ]; then \
		cd $(DATA_DIR) && git submodule add https://github.com/epic-kitchens/$(EK_DL_NAME) ; \
	fi


.PHONY: weights-asf
weights-asf:
	@mkdir -p models/asf/weights
	@wget https://www.dropbox.com/s/cr0c6xdaggc2wzz/$(ASF_WEIGHTS_FILE) -O models/asf/weights/$(ASF_WEIGHTS_FILE)

.PHONY: update
update:
	@git submodule sync --recursive
	@git submodule update --init --recursive
	@git pull --recurse-submodules


.PHONY: bash
bash:
	@echo "Running interactive bash session"
	@srun --job-name "interactive bash" \
		--cpus-per-task 8 \
		--mem 16G \
		--time 12:00:00 \
		--pty bash

.PHONY: bash-gpu
bash-gpu:
	@echo "Running interactive bash session"
	@srun --job-name "interactive bash" \
		--cpus-per-task 4 \
		--mem 16G \
		--gres gpu:1 \
		--time 12:00:00 \
		--pty bash

.PHONY: queue
queue:
	@squeue -u $(USER)

.PHONY: example-cluster
example-cluster:
	@python main.py \
		--model audio_slowfast \
		--config config.yaml \
		--example $(EXAMPLE_FILE) \
		--verbs break crush pat shake sharpen smell throw water

.PHONY: example-local
example-local:
	@python main.py \
		--model audio_slowfast \
		--config config.local.yaml \
		--example $(EXAMPLE_FILE) \
		--make-plots \
		--verbs break crush pat shake sharpen smell throw water

.PHONY: example
example:
	@if echo "$(shell hostname)" | grep -q "nyu"; then \
		echo "Running on cluster"; \
		$(MAKE) example-cluster; \
	else \
		echo "Running locally"; \
		$(MAKE) example-local; \
	fi


.PHONY: lint
lint: # This target runs the formatter (black), linter (ruff) and sorts imports (isort)
	@isort . --skip $(DATA_DIR)/ --profile black
	@ruff . --fix --line-length 120 --show-source --exclude ./$(DATA_DIR) --force-exclude -v
	@black . --force-exclude ./$(DATA_DIR) --line-length 120 --color


.PHONY: test
test:
	@pytest --ignore-glob $(DATA_DIR) -v --code-highlight yes --capture no

.PHONY: update-deps
update-deps:
	@pip install -U -r requirements.txt

.PHONY: train
train:
	@$(CONDA_ACTIVATE) $(VENV_DIR)
	python main.py \
		--model audio_slowfast \
		--config config.yaml \
		--train \
		--verbs break crush pat shake sharpen smell throw water

.PHONY: reinstall-asf
reinstall-asf:
	@$(CONDA_ACTIVATE) $(VENV_DIR)
	@pip uninstall audio-slowfast -y
	@pip install -U --no-cache-dir git+https://github.com/ClementSicard/auditory-slow-fast.git@main

.PHONY: reload
reload:
	$(MAKE) reinstall-asf
	@rm -rf checkpoints/
	$(MAKE) train

.PHONY: job
job:
	@mkdir -p $(LOGS_DIR)
	@DATE=$$(date +"%Y_%m_%d-%T"); \
	LOG_FILE="$(REPO_DIR)/$(LOGS_DIR)/$${DATE}-slowfast-train.log"; \
	sbatch -N 1 \
	    --ntasks 1 \
	    --cpus-per-task 4 \
	    --gres gpu:1 \
	    --time 12:00:00 \
	    --mem 16G \
	    --error $${LOG_FILE} \
	    --output $${LOG_FILE} \
	    --job-name $(JOB_NAME) \
	    --open-mode append \
	    --mail-type "BEGIN,END" \
		--mail-user $(MAIL_ADDRESS) \
	    --wrap "cd $(REPO_DIR) && make train"
