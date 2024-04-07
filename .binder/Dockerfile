#BEGIN: jupyter/datascience-notebook
#HACK: pin Jupyter Lab 3.x to ensure WebIO.jl (Interact.jl) working
FROM jupyter/scipy-notebook:lab-3.6.3

# Fix: https://github.com/hadolint/hadolint/wiki/DL4006
# Fix: https://github.com/koalaman/shellcheck/wiki/SC3014
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root

# Julia installation
# Default values can be overridden at build time
# (ARGS are in lower case to distinguish them from ENV)
# Check https://julialang.org/downloads/
ARG julia_version="1.10.2"

# R pre-requisites
RUN apt-get update --yes && \
    apt-get install --yes --no-install-recommends \
    fonts-dejavu \
    gfortran \
    gcc && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Julia dependencies
# install Julia packages in /opt/julia instead of ${HOME}
ENV JULIA_DEPOT_PATH=/opt/julia \
    JULIA_PKGDIR=/opt/julia \
    JULIA_VERSION="${julia_version}"

WORKDIR /tmp

# hadolint ignore=SC2046
RUN set -x && \
    julia_arch=$(uname -m) && \
    julia_short_arch="${julia_arch}" && \
    if [ "${julia_short_arch}" == "x86_64" ]; then \
      julia_short_arch="x64"; \
    fi; \
    julia_installer="julia-${JULIA_VERSION}-linux-${julia_arch}.tar.gz" && \
    julia_major_minor=$(echo "${JULIA_VERSION}" | cut -d. -f 1,2) && \
    mkdir "/opt/julia-${JULIA_VERSION}" && \
    wget --progress=dot:giga "https://julialang-s3.julialang.org/bin/linux/${julia_short_arch}/${julia_major_minor}/${julia_installer}" && \
    tar xzf "${julia_installer}" -C "/opt/julia-${JULIA_VERSION}" --strip-components=1 && \
    rm "${julia_installer}" && \
    ln -fs /opt/julia-*/bin/julia /usr/local/bin/julia

# Show Julia where conda libraries are \
RUN mkdir /etc/julia && \
    echo "push!(Libdl.DL_LOAD_PATH, \"${CONDA_DIR}/lib\")" >> /etc/julia/juliarc.jl && \
    # Create JULIA_PKGDIR \
    mkdir "${JULIA_PKGDIR}" && \
    chown "${NB_USER}" "${JULIA_PKGDIR}" && \
    fix-permissions "${JULIA_PKGDIR}"

USER ${NB_UID}

# R packages including IRKernel which gets installed globally.
# r-e1071: dependency of the caret R package
RUN mamba install --yes \
    'r-base' \
    'r-caret' \
    'r-crayon' \
    'r-devtools' \
    'r-e1071' \
    'r-forecast' \
    'r-hexbin' \
    'r-htmltools' \
    'r-htmlwidgets' \
    'r-irkernel' \
    'r-nycflights13' \
    'r-randomforest' \
    'r-rcurl' \
    'r-rmarkdown' \
    'r-rodbc' \
    'r-rsqlite' \
    'r-shiny' \
    'r-tidymodels' \
    'r-tidyverse' \
    'rpy2' \
    'unixodbc' && \
    mamba clean --all -f -y && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"

# Add Julia packages.
# Install IJulia as jovyan and then move the kernelspec out
# to the system share location. Avoids problems with runtime UID change not
# taking effect properly on the .local folder in the jovyan home dir.
RUN julia -e 'import Pkg; Pkg.update()' && \
    julia -e 'import Pkg; Pkg.add("HDF5")' && \
    julia -e 'using Pkg; pkg"add IJulia"; pkg"precompile"' && \
    # move kernelspec out of home \
    mv "${HOME}/.local/share/jupyter/kernels/julia"* "${CONDA_DIR}/share/jupyter/kernels/" && \
    chmod -R go+rx "${CONDA_DIR}/share/jupyter" && \
    rm -rf "${HOME}/.local" && \
    fix-permissions "${JULIA_PKGDIR}" "${CONDA_DIR}/share/jupyter"

WORKDIR "${HOME}"
#END: jupyter/datascience-notebook

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
RUN julia -e 'using Pkg; pkg"add Cairo CairoMakie CSV DataFrames DataFramesMeta DataStructures Distributions Fontconfig Gadfly Plots StatsBase StatsPlots TimeZones TypedTables Unitful WGLMakie";'

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
