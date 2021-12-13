# See the NOTICE file distributed with this work for additional information
# regarding copyright ownership.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""Unit testing of `orthology_benchmark.py` script.

Typical usage example::

    $ pytest test_orthology_benchmark.py

"""

from contextlib import nullcontext as does_not_raise
from importlib.abc import Loader
from importlib.machinery import ModuleSpec
from importlib.util import module_from_spec, spec_from_file_location
import os
from pathlib import Path
import sys
from typing import ContextManager, Dict, List

import sqlalchemy

import pytest
from pytest import FixtureRequest, raises

from ensembl.compara.filesys import file_cmp


script_path = Path(__file__).parents[3] / "scripts" / "pipeline" / "orthology_benchmark.py"
script_name = script_path.stem
script_spec = spec_from_file_location(script_name, script_path)

if not isinstance(script_spec, ModuleSpec):
    raise ImportError(f"ModuleSpec not created for module file '{script_path}'")
if not isinstance(script_spec.loader, Loader):
    raise ImportError(f"no loader found for module file '{script_path}'")

orthology_benchmark_module = module_from_spec(script_spec)
sys.modules[script_name] = orthology_benchmark_module
script_spec.loader.exec_module(orthology_benchmark_module)

# pylint: disable=import-error,wrong-import-position,wrong-import-order

import orthology_benchmark  # type: ignore

# pylint: enable=import-error,wrong-import-position,wrong-import-order


@pytest.mark.parametrize(
    "multi_dbs",
    [
        [{'src': 'core/gallus_gallus_core_99_6'}, {'src': 'core/homo_sapiens_core_99_38'}]
    ],
    indirect=True
)
class TestDumpGenomes:
    """Tests :func:`orthology_benchmark.dump_genomes()` function.

    Attributes:
        core_dbs: A set of test core databases.

    """

    core_dbs = {}  # type: Dict
    host = None  # type: str
    port = None  # type: int
    username = None  # type: str

    # autouse=True makes this fixture be executed before any test_* method of this class, and scope='class' to
    # execute it only once per class parametrization
    @pytest.fixture(scope='class', autouse=True)
    def setup(self, request: FixtureRequest, multi_dbs: Dict) -> None:
        """Loads the required fixtures and values as class attributes.

        Args:
            request: Access to the requesting test context.
            multi_dbs: Dictionary of unit test databases (fixture).

        """
        type(self).core_dbs = multi_dbs
        server_url = sqlalchemy.engine.url.make_url(request.config.getoption('server'))
        type(self).host = server_url.host
        type(self).port = server_url.port
        type(self).username = "ensro" if server_url.username == "ensadmin" else server_url.username

    @pytest.mark.skipif(os.environ['USER'] == 'travis',
                        reason="The test requires both Perl and Python which is not supported by Travis.")
    @pytest.mark.parametrize(
        "species_list, species_set_name, expectation",
        [
            (["gallus_gallus", "homo_sapiens"], "default", does_not_raise()),
            (["homo_sapiens", "zea_mays"], "default", raises(FileExistsError)),
            (["felis_catus", "zea_mays"], "test", raises(RuntimeError,
                    match=r"No cores found for the species set 'test' on the specified host."))
        ]
    )
    def test_dump_genomes(self, species_list: List[str], species_set_name: str,
                          tmp_dir: Path, expectation: ContextManager) -> None:
        """Tests :func:`orthology_benchmark.dump_genomes()` when server connection can be established.

        Args:
            species_list: A list of species (genome names).
            species_set_name: Species set (collection) name.
            tmp_dir: Unit test temp directory (fixture).
            expectation: Context manager for the expected exception, i.e. the test will only pass if that
                exception is raised. Use :class:`~contextlib.nullcontext` if no exception is expected.

        """
        with expectation:
            orthology_benchmark.dump_genomes(species_list, species_set_name, self.host, self.port,
                                             self.username, tmp_dir)

            out_files = tmp_dir / species_set_name
            # pylint: disable-next=no-member
            exp_out = pytest.files_dir / "orth_benchmark"  # type: ignore[attr-defined]
            for db_name, unittest_db in self.core_dbs.items():
                assert file_cmp(out_files / f"{unittest_db.dbc.db_name}.fasta", exp_out / f"{db_name}.fasta")

    def test_dump_genomes_fake_connection(self, tmp_dir: Path) -> None:
        """Tests :func:`orthology_benchmark.dump_genomes()` with fake server details.

        Args:
            tmp_dir: Unit test temp directory (fixture).

        """
        with raises(sqlalchemy.exc.OperationalError):
            orthology_benchmark.dump_genomes(["mus_musculus", "naja_naja"], "default",
                                             "fake-host", 65536, "compara", tmp_dir)


@pytest.mark.parametrize(
    "core_names, exp_output, expectation",
    [
        (["mus_musculus_core_105_1", "mus_musculus_core_52_105_3", "mus_musculus_core_104_4"],
         "mus_musculus_core_52_105_3", does_not_raise()),
        ([], None, raises(ValueError,
                          match=r"Empty list of core databases. Cannot determine the latest one."))
    ]
)
def test_find_latest_core(core_names: List[str], exp_output: str, expectation: ContextManager) -> None:
    """Tests :func:`orthology_benchmark.find_latest_core()` function.

    Args:
        core_names: A list of core database names.
        exp_output: Expected return value of the function.
        expectation: Context manager for the expected exception, i.e. the test will only pass if that
            exception is raised. Use :class:`~contextlib.nullcontext` if no exception is expected.

    """
    with expectation:
        assert orthology_benchmark.find_latest_core(core_names) == exp_output


@pytest.mark.parametrize(
    "multi_dbs",
    [
        [{'src': 'core/danio_rerio_core_105_11'}, {'src': 'core/mus_musculus_cbaj_core_107_1'},
         {'src': 'core/mus_musculus_core_106_39'}]
    ],
    indirect=True
)
class TestGetCoreNames:
    """Tests :func:`orthology_benchmark.get_core_names()` function.

    Attributes:
        core_dbs: A set of test core databases.

    """

    core_dbs = {}  # type: Dict
    host = None  # type: str
    port = None  # type: int
    username = None  # type: str

    # autouse=True makes this fixture be executed before any test_* method of this class, and scope='class' to
    # execute it only once per class parametrization
    @pytest.fixture(scope='class', autouse=True)
    def setup(self, request: FixtureRequest, multi_dbs: Dict) -> None:
        """Loads the required fixtures and values as class attributes.

        Args:
            request: Access to the requesting test context.
            multi_dbs: Dictionary of unit test databases (fixture).

        """
        type(self).core_dbs = multi_dbs
        server_url = sqlalchemy.engine.url.make_url(request.config.getoption('server'))
        type(self).host = server_url.host
        type(self).port = server_url.port
        type(self).username = "ensro" if server_url.username == "ensadmin" else server_url.username

    @pytest.mark.parametrize(
        "species_names, exp_output, expectation",
        [
            (["danio_rerio", "mus_musculus", "zea_mays"],
             {"danio_rerio": os.environ['USER'] + "_danio_rerio_core_105_11",
              "mus_musculus": os.environ['USER'] + "_mus_musculus_core_106_39"},
             does_not_raise()),
            ([], None, raises(ValueError,
                              match=r"Empty list of species names. Cannot search for core databases."))
        ]
    )
    def test_get_core_names(self, species_names: List[str], exp_output: Dict[str, str],
                            expectation: ContextManager) -> None:
        """Tests :func:`orthology_benchmark.get_core_names()` when server connection can be established.

        Args:
            species_names: Species (genome) names.
            exp_output: Expected return value of the function.
            expectation: Context manager for the expected exception, i.e. the test will only pass if that
                exception is raised. Use :class:`~contextlib.nullcontext` if no exception is expected.

        """
        with expectation:
            assert orthology_benchmark.get_core_names(species_names, self.host, self.port,
                                                      self.username) == exp_output

    def test_get_core_names_fake_connection(self) -> None:
        """Tests :func:`orthology_benchmark.get_core_names()` with fake server details."""
        with raises(sqlalchemy.exc.OperationalError):
            orthology_benchmark.get_core_names(["danio_rerio", "mus_musculus"], "fake-host", 65536, "compara")
