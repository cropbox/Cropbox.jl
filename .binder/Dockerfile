ARG JULIA_VERSION=1.9.2
FROM jupyter/datascience-notebook:julia-${JULIA_VERSION}
ARG JULIA_VERSION
ENV JULIA_VERSION=${JULIA_VERSION}

# set up repository for repo2docker
ARG REPO_DIR=${HOME}
ENV REPO_DIR=${REPO_DIR}
WORKDIR ${REPO_DIR}
COPY --chown=${NB_USER}:users . ${REPO_DIR}

#HACK: ensure REPO_DIR is fully owned by user to avoid Git `safe.directory` issue
USER root
RUN chown -R ${NB_USER}:users ${REPO_DIR}

# install as non-root
USER ${NB_USER}

# avoid config/data in home which can be replaced
ENV JUPYTER_CONFIG_DIR=/opt/conda/etc/jupyter
ENV JUPYTER_DATA_DIR=/opt/conda/share/jupyter

# install necessary Jupyter modules
RUN pip install \
    'jupyter-server-proxy' \
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

# clean up as root
USER root

# create a wrapper for Julia REPL with custom system image
RUN rm /usr/local/bin/julia && \
    echo -e '#!/bin/bash\n/opt/julia-'${JULIA_VERSION}'/bin/julia -J'${CROPBOX_IMG} '"$@"' > /usr/local/bin/julia && \
    chmod +x /usr/local/bin/julia

RUN chown -R ${NB_USER}:users ${HOME} && \
    chown -R ${NB_USER}:users ${JULIA_DEPOT_PATH}

WORKDIR ${HOME}
USER ${NB_USER}
