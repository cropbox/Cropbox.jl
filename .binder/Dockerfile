FROM jupyter/datascience-notebook:2021-10-07

# set up repository for repo2docker
ARG REPO_DIR=${HOME}
ENV REPO_DIR=${REPO_DIR}
WORKDIR ${REPO_DIR}
USER root
COPY --chown=${NB_USER}:users . ${REPO_DIR}

# avoid config/data in home which can be replaced
ENV JUPYTER_CONFIG_DIR=/opt/conda/etc/jupyter
ENV JUPYTER_DATA_DIR=/opt/conda/share/jupyter

# install necessary Jupyter modules
RUN pip install \
    'nbgitpuller' \
    'nbresuse' \
    'webio_jupyter_extension'

# ensure Cropbox.jl added/built and available outside home directory
ENV JULIA_PROJECT=""
ENV CROPBOX_DIR=${REPO_DIR}
RUN julia -e 'import Pkg; Pkg.add(url="'${CROPBOX_DIR}'"); Pkg.build("Cropbox");'

# install commonly used packages
RUN julia -e 'using Pkg; pkg"add CSV DataFrames DataFramesMeta DataStructures Dates Distributions Gadfly StatsBase Test TimeZones TypedTables Unitful";'

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