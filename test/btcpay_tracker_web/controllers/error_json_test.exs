defmodule BtcpayTrackerWeb.ErrorJSONTest do
  use BtcpayTrackerWeb.ConnCase, async: true

  test "renders 404" do
    assert BtcpayTrackerWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert BtcpayTrackerWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
