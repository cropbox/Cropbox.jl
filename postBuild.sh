#!/bin/bash

# set up WebIO.jl for Interact.jl support
export JUPYTER_CONFIG_DIR=${NB_PYTHON_PREFIX}/etc/jupyter
JULIA_PROJECT="" julia -e "using Pkg; Pkg.add(\"WebIO\"); using WebIO; WebIO.install_jupyter_nbextension(nbextension_flags=\`--sys-prefix\`); WebIO.install_jupyter_labextension();"

# trigger build of JupyterLab for Jupytext
#HACK: triggered by WebIO.install_jupyter_labextension()
#jupyter lab build

# ensure Cropbox.jl added/built and available outside home directory
export CROPBOX_DIR=${REPO_DIR}
JULIA_PROJECT="" julia -e "import Pkg; Pkg.add(url=\"${CROPBOX_DIR}\"); Pkg.build(\"Cropbox\");"

# install commonly used packages
JULIA_PROJECT="" julia -e "using Pkg; pkg\"add CSV DataFrames DataFramesMeta DataStructures Distributions Gadfly StatsBase TimeZones TypedTables Unitful WGLMakie\";"

# install Cropbox-related packages
JULIA_PROJECT="" julia -e "using Pkg; pkg\"add CropRootBox Garlic LeafGasExchange SimpleCrop\";"

# fallback system image in case PackageCompiler fails
export CROPBOX_IMG=${CROPBOX_DIR}/cropbox.so
ln -s ${JULIA_PATH}/lib/julia/sys.so ${CROPBOX_IMG}

# create a system image with Cropbox built-in
julia -e "import Pkg; Pkg.add(\"Test\");"
julia -e "import Pkg; Pkg.add(\"PackageCompiler\"); using PackageCompiler; create_sysimage(:Cropbox; sysimage_path=\"${CROPBOX_IMG}\", precompile_execution_file=\"${REPO_DIR}/.binder/precompile.jl\", cpu_target=PackageCompiler.default_app_cpu_target());" || exit 1

# update IJulia kernel with custom system image
JULIA_PROJECT="" julia -e "using IJulia; installkernel(\"Julia\", \"--project=${HOME}\", \"--sysimage=${CROPBOX_IMG}\");"

# create a wrapper of Julia REPL with custom system image
mkdir -p ${REPO_DIR}/.local/bin
echo -e '#!/bin/bash\n'"${JULIA_PATH}/bin/julia -J${CROPBOX_IMG}" '"$@"' > ${REPO_DIR}/.local/bin/julia
chmod +x ${REPO_DIR}/.local/bin/julia
