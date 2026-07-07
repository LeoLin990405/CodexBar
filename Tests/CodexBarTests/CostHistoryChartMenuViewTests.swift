import Testing
@testable import CodexBar

struct CostHistoryChartMenuViewTests {
    @Test
    @MainActor
    func `window label keeps today for one day and dynamic labels otherwise`() {
        #expect(CostHistoryChartMenuView.windowLabel(days: 1) == "Today")
        #expect(CostHistoryChartMenuView.windowLabel(days: 7) == "Last 7 days")
        #expect(CostHistoryChartMenuView.windowLabel(days: 30) == "Last 30 days")
    }

    @Test
    @MainActor
    func `y axis ticks include min midpoint and max for varied costs`() {
        let ticks = CostHistoryChartMenuView.yAxisTickValues(for: [0.25, 2.25, 1.0])

        #expect(ticks == [0.25, 1.25, 2.25])
    }

    @Test
    @MainActor
    func `y axis ticks include zero and max for flat nonzero costs`() {
        let ticks = CostHistoryChartMenuView.yAxisTickValues(for: [1.5, 1.5, 1.5])

        #expect(ticks == [0, 1.5])
    }

    @Test
    @MainActor
    func `y axis ticks collapse zero only cost data`() {
        let ticks = CostHistoryChartMenuView.yAxisTickValues(for: [0, 0])

        #expect(ticks == [0])
    }

    @Test
    @MainActor
    func `y axis ticks ignore invalid and negative costs`() {
        let ticks = CostHistoryChartMenuView.yAxisTickValues(for: [
            -.infinity,
            -1,
            0.5,
            .nan,
            .infinity,
            1.5,
        ])

        #expect(ticks == [0.5, 1.0, 1.5])
    }

    @Test
    @MainActor
    func `y axis labels use compact currency strings and drop duplicates`() {
        let labels = CostHistoryChartMenuView.yAxisTickLabels(
            for: [0.001, 0.004, 0.01],
            currencyCode: "USD")

        #expect(labels[0.001] == "$0.00")
        #expect(labels[0.004] == nil)
        #expect(labels[0.01] == "$0.01")
    }
}
