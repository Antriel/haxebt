class TestsMain {

    public static function main() {
        var runner = new utest.Runner();
        runner.addCase(new TestManual());
        runner.addCase(new TestParsed());
        utest.ui.Report.create(runner);
        runner.run();
    }

}
