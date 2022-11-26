FROM jupyter/datascience-notebook:julia-1.8.3

# set up repository for repo2docker
ARG REPO_DIR=${HOME}
ENV REPO_DIR=${REPO_DIR}
WORKDIR ${REPO_DIR}
USER root
COPY --chown=${NB_USER}:users . ${REPO_DIR}

# avoid config/data in home which can be replaced
ENV JUPYTER_CONFIG_DIR=/opt/conda/etc/jupyter
ENV JUPYTER_DATA_DIR=/opt/conda/share/jupyter

# install RStudio
ENV RSTUDIO_URL=https://download2.rstudio.org/server/jammy/amd64/rstudio-server-2022.07.2-576-amd64.deb
RUN wget -O /tmp/rstudio.deb ${RSTUDIO_URL} && \
    apt-get update && \
    apt install -y /tmp/rstudio.deb && \
    rm /tmp/rstudio.deb && \
    apt-get -qq purge && \
    apt-get -qq clean && \
    rm -rf /var/lib/apt/lists/*

# adjust RStudio permission
RUN chown -R ${NB_USER}:users /var/lib/rstudio-server

# configure RStudio
ENV RSESSION_PROXY_RSTUDIO_1_4=1
RUN echo "server-user=${NB_USER}" >> /etc/rstudio/rserver.conf && \
    echo auth-none=1 >> /etc/rstudio/rserver.conf && \
    echo auth-minimum-user-id=0 >> /etc/rstudio/rserver.conf && \
    echo rsession-which-r=/opt/conda/bin/R >> /etc/rstudio/rserver.conf && \
    echo www-frame-origin=same >> /etc/rstudio/rserver.conf

# install R packages
RUN mamba install --quiet --yes --channel conda-forge \
    'tensorflow' \
    'r-tidyverse' \
    'r-tensorflow' \
    'r-keras' \
    'r-tfdatasets' \
    'r-randomforest' \
    'r-skimr' \
    'r-hydrogof' && \
    mamba clean --all -f -y && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"

# install necessary Jupyter modules
RUN pip install \
    'jupyter-server-proxy' \
    'jupyter-rsession-proxy' \
    'jupyter-shiny-proxy' \
    'nbgitpuller' \
    'nbresuse' \
    'webio_jupyter_extension'

# ensure Cropbox.jl added/built and available outside home directory
ENV JULIA_PROJECT=""
ENV CROPBOX_DIR=${REPO_DIR}
RUN julia -e 'import Pkg; Pkg.add(url="'${CROPBOX_DIR}'"); Pkg.build("Cropbox");'

# install commonly used packages
RUN julia -e 'using Pkg; pkg"add CSV DataFrames DataFramesMeta DataStructures Distributions Gadfly StatsBase TimeZones TypedTables Unitful WGLMakie";'

# install MLJ packages
RUN julia -e 'using Pkg; pkg"add MLJ MLJModels MLJLinearModels MLJDecisionTreeInterface DecisionTree MLJFlux Flux Plots";'

#HACK: ensure MKL_jll artifacts downloaded (perhaps an issue with PackageCompiler 1.6+)
RUN julia -e 'import Pkg; Pkg.add("MKL_jll"); using MKL_jll;'

# install Cropbox-related packages
RUN julia -e 'using Pkg; pkg"add CropRootBox Garlic LeafGasExchange SimpleCrop";'

# create a system image with Cropbox built-in
ENV CROPBOX_IMG=${CROPBOX_DIR}/cropbox.so
RUN julia -e 'import Pkg; Pkg.add("PackageCompiler"); using PackageCompiler; create_sysimage(:Cropbox; sysimage_path="'${CROPBOX_IMG}'", precompile_execution_file="'${REPO_DIR}'/.binder/precompile.jl", cpu_target=PackageCompiler.default_app_cpu_target());' || exit 1

# update IJulia kernel with custom system image
RUN julia -e 'using IJulia; installkernel("Julia", "--project='${HOME}'", "--sysimage='${CROPBOX_IMG}'");'

# create a wrapper for Julia REPL with custom system image
RUN rm /usr/local/bin/julia && \
    echo -e '#!/bin/bash\n/opt/julia-'${JULIA_VERSION}'/bin/julia -J'${CROPBOX_IMG} '"$@"' > /usr/local/bin/julia && \
    chmod +x /usr/local/bin/julia

RUN chown -R ${NB_USER}:users ${HOME} && \
    chown -R ${NB_USER}:users ${JULIA_DEPOT_PATH}

WORKDIR ${HOME}
USER ${NB_USER}
