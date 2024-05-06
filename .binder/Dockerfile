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
ARG julia_version="1.10.3"

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
    JULIA_VERSION="${julia_version}" \
    JULIA_CPU_TARGET=generic

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

# clean up as root
USER root

RUN chown -R ${NB_USER}:users ${HOME} && \
    chown -R ${NB_USER}:users ${JULIA_DEPOT_PATH}

WORKDIR ${HOME}
USER ${NB_USER}
