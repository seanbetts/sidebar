import pytest
from api.metrics import tool_execution_duration_seconds, tool_executions_total
from api.services.tool_mapper import ToolMapper


def _counter_value(counter, *labels: str) -> float:
    return counter.labels(*labels)._value.get()


def _histogram_count(histogram, label_name: str, label_value: str) -> float:
    samples = histogram.collect()[0].samples
    for sample in samples:
        if (
            sample.name.endswith("_count")
            and sample.labels.get(label_name) == label_value
        ):
            return sample.value
    return 0.0


@pytest.mark.asyncio
async def test_tool_metrics_increment_for_ui_theme():
    mapper = ToolMapper()
    tool_name = mapper.tool_name_reverse["Set UI Theme"]
    skill_id = "ui-theme"

    start_total = _counter_value(tool_executions_total, skill_id, "success")
    start_count = _histogram_count(
        tool_execution_duration_seconds, "skill_id", skill_id
    )

    result = await mapper.execute_tool(tool_name, {"theme": "dark"})
    assert result["success"] is True

    end_total = _counter_value(tool_executions_total, skill_id, "success")
    end_count = _histogram_count(tool_execution_duration_seconds, "skill_id", skill_id)

    assert end_total == start_total + 1
    assert end_count == start_count + 1
