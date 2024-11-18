# Installation

This workflow can be used as module within a super-project by installing it as a [git submodule](https://git-scm.com/book/en/v2/Git-Tools-Submodules).
```
git submodule add git@github.com:swarbricklab/genotyping.git modules/genotyping
```
This will create a clone of this repo at `modules/genotyping` within the super project.

If you are working on a project where this workflow has been installed as a submodule, note that submodules are not checked out by default when you `git clone` the super-project.
You can include submodules by cloning as follows:
```
git clone --recurse-submodules {repository_url}
```

If you forget to do this while cloning, then you can initialise all submodules and bring them up to date with the following command: 
```
git submodule update --init --recursive
```

Alternatively, you can run
```
dt_clone {repository_url}
```
The `dt_clone` command is available within DVC environments on NCI.
This command checks out submodules and sets the DVC cache to a shared location.
